# CLAUDE.md — Stockops-Infra

> 이 파일을 `C:\KJW\Team_Project\Stockops-Infra\CLAUDE.md` 에 저장하세요.
> Claude Code가 이 디렉터리(또는 하위 `seoul/`, `ohio/`, `global/`)에서 세션을 시작할 때마다 자동으로 로드됩니다.

## 이 저장소

StockOps 멀티리전 AWS 인프라(Terraform IaC). 3개의 독립된 state로 분리되어 있음:
`infra/seoul`(primary), `infra/ohio`(failover), `infra/global`(Route53/ACM/Global Accelerator).
global은 seoul/ohio의 output을 `terraform_remote_state`로 참조하므로 **순서에 의존성이 있음**.

**VPC Peering 관리 방식:** Seoul ↔ Ohio 피어링은 `seoul/peering.tf` 단일 파일에서 전부 관리한다.
Seoul state가 피어링 연결·수락·양방향 라우트를 모두 소유하며, Ohio alias provider(`provider "aws" { alias = "ohio" }`)를 통해 Ohio 측 리소스도 Seoul state에서 조작한다.
이 설계로 인해 **VPC Peering이 Apply/Destroy 순서에 영향을 준다** (아래 참조).

## 자동 실행 원칙 (가장 중요)

- terraform plan/apply/destroy를 실행할 때 **반드시 `-auto-approve`를 붙인다.** 이게 없으면 terraform이 콘솔에서 "yes"를 기다리며 멈춘다 — Claude Code의 권한 프롬프트와는 별개의 문제이니 항상 플래그로 해결한다.
- 작업 시작 전 "진행해도 될까요?", "destroy 할까요?" 같은 확인을 사용자에게 구하지 않는다. 사용자가 이미 apply/destroy를 요청했다면 끝까지 실행한다.
- 중간 단계마다 보고하지 않는다. 전체 작업(예: 3개 region apply, 또는 전체 destroy)이 끝난 뒤 결과를 한 번에 간결히 요약 보고한다. 진행 중 발생한 에러와 그 해결 방법은 요약에 포함한다.
- 에러가 발생하면 먼저 아래 "알려진 트러블슈팅 패턴"에서 해당하는 항목을 찾아 직접 해결을 시도한다. 사용자에게 "어떻게 할까요?"라고 묻지 않는다. 패턴에 없는 새로운 에러라면 원인을 분석하고 합리적인 해결책을 직접 적용한 뒤, 무엇을 왜 했는지 사후 보고한다.

## Apply / Destroy 순서

### Apply (전체 신규 구축)

```
1. Seoul   → VPC·EKS·RDS·Secrets 등 core 리소스 생성
             ※ peering.tf는 Ohio VPC가 없어 실패할 수 있음 → 무시하고 다음 단계로
2. Ohio    → VPC·EKS·RDS 생성 (Seoul remote state 참조)
3. Seoul   → 재실행 (Ohio VPC가 생긴 후 peering.tf가 성공, 피어링 + 라우트 생성)
4. Global  → Route53·ACM·CloudFront·WAF 생성 (Seoul/Ohio ALB ARN 참조)
```

### Apply (Seoul 살아있는 상태에서 Ohio만 재구축)

```
1. Ohio    → 신규 VPC·EKS·RDS 생성
2. Seoul   → peering.tf가 새 Ohio VPC를 감지, 피어링 재연결 + 라우트 재생성
             ※ seoul/peering.tf의 ohio_private_rt_ids 하드코딩 RT ID가 바뀌었으면 먼저 갱신 (아래 주의사항 참조)
3. Global  → 이미 존재하면 no-op, 재구축이면 신규 생성
```

### Destroy (전체)

> **핵심 제약:**
> - VPC Peering(Seoul state 소유)이 존재하면 Ohio VPC를 삭제할 수 없음 → **Seoul peering 먼저 제거**
> - Ohio RDS Replica가 Seoul RDS Primary를 참조 → **Ohio를 Seoul보다 먼저 destroy**

```
1. Global  → CloudFront·WAF·ACM·Route53 레코드 삭제
2. Seoul   → peering 리소스만 targeted destroy (Ohio VPC 삭제 블록 해제)
             terraform -chdir=seoul destroy -auto-approve \
               -target=aws_vpc_peering_connection_accepter.ohio \
               -target=aws_vpc_peering_connection_options.ohio \
               -target=aws_vpc_peering_connection_options.seoul \
               -target=aws_vpc_peering_connection.seoul_to_ohio \
               -target='aws_route.seoul_to_ohio["<rt-id-1>"]' \
               -target='aws_route.seoul_to_ohio["<rt-id-2>"]' \
               -target='aws_route.seoul_to_ohio["<rt-id-3>"]' \
               -target='aws_route.ohio_to_seoul["<rt-id-1>"]' \
               -target='aws_route.ohio_to_seoul["<rt-id-2>"]' \
               -target='aws_route.ohio_to_seoul["<rt-id-3>"]'
3. Ohio    → 전체 destroy (VPC 포함)
4. Seoul   → 전체 destroy (RDS Primary 등)
```

## 알려진 트러블슈팅 패턴 (자동 해결)

| 증상 | 해결 |
|---|---|
| IoT policy/Thing이 연결된 상태에서 destroy 실패 | destroy 전에 AWS CLI로 IoT policy/Thing을 인증서에서 먼저 detach |
| PowerShell에서 ECR 로그인 시 토큰 깨짐 | `aws ecr get-login-password \| Out-File -Encoding ascii` 후 그 파일을 `docker login`에 파이프 (파이프 연산자로 직접 넘기면 인코딩이 깨짐) |
| RDS parameter group 삭제가 막힘 | 해당 parameter group을 쓰는 RDS 인스턴스가 아직 살아있는지 확인, 인스턴스 삭제 완료 후 재시도 |
| ECR repo가 destroy 대상에 포함되어 있음 | ECR은 `data` source로 유지해야 destroy cycle에서 안전 — `resource`로 되어있다면 `data`로 전환 |
| `terraform destroy` 중 ArgoCD CRD 관련 kubectl 에러 | 무시 가능, destroy를 막지 않음 |
| `helm_release.argocd`가 "Still destroying..."로 멈춤 | 1) `kubectl get applications -n argocd` 확인 2) 각 Application에 `kubectl patch application <name> -n argocd --type merge -p '{"metadata":{"finalizers":null}}'` 로 finalizer 제거 3) `kubectl delete namespace argocd --grace-period=0 --force` 4) 그래도 안 풀리면 terraform 프로세스 kill → `terraform force-unlock <lock-id>` → `terraform state rm helm_release.argocd kubernetes_namespace_v1.stockops` → destroy 재실행 |
| terraform 프로세스가 백그라운드에서 state lock을 잡은 채 멈춤 | `Get-Process terraform \| Stop-Process -Force` 로 프로세스 종료 → lock ID 확인 후 `terraform force-unlock -force <lock-id>` |
| subnet destroy가 "Still destroying..."로 멈춤 | `aws ec2 describe-network-interfaces --filters "Name=subnet-id,Values=<id>"`로 ENI 확인 → `available` 상태면 `aws ec2 delete-network-interface`로 직접 삭제 → `in-use`면 원인 리소스(ELB/Lambda/EKS 노드) 먼저 정리 |
| Ohio VPC destroy 시 "DependencyViolation" 오류 | VPC Peering이 남아있는 것이 원인. `aws ec2 describe-vpc-peering-connections --region us-east-2 --filters "Name=accepter-vpc-info.vpc-id,Values=<vpc-id>"` 로 pcx 확인 → `aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id <pcx-id> --region us-east-2` 로 삭제 → Seoul state에서도 peering 항목 state rm (아래 참조) |
| Ohio destroy 후 Seoul state에 peering 관련 항목이 남음 | `terraform -chdir=seoul state rm aws_vpc_peering_connection.seoul_to_ohio aws_vpc_peering_connection_accepter.ohio aws_vpc_peering_connection_options.ohio aws_vpc_peering_connection_options.seoul 'aws_route.ohio_to_seoul["rtb-xxx"]'` … 총 10개 항목 제거 후 Seoul apply 재실행 |
| Ohio VPC 재생성 후 Seoul peering.tf의 Ohio RT ID가 맞지 않음 | `aws ec2 describe-route-tables --region us-east-2 --filters "Name=tag:Name,Values=ohio-priv-app-rt,ohio-priv-db-rt,ohio-pub-rt" --query "RouteTables[*].[RouteTableId,Tags[?Key=='Name'].Value\|[0]]" --output text` 로 새 ID 확인 → `seoul/peering.tf`의 `ohio_private_rt_ids` 업데이트 후 Seoul apply |
| IoT 인증서가 `var.iot_certificate_arn`으로 참조됨 | destroy cycle을 살리기 위한 의도된 설계이므로 변경하지 않음 |

새로운 패턴을 발견하면 이 표에 추가해서 다음 세션에도 재사용한다.

## VPC Peering 관련 주의사항

- `seoul/peering.tf`의 `ohio_private_rt_ids`는 **Ohio RT ID를 하드코딩**하고 있음. Ohio VPC가 재생성되면 RT ID가 바뀌므로 반드시 갱신해야 한다.
- Seoul 측 RT ID(`seoul_rt_ids`)는 VPC 모듈 output(`pub_rt_id`, `priv_app_rt_id`, `priv_db_rt_id`)을 참조하므로 Seoul VPC 재생성 시 자동 갱신됨. 별도 작업 불필요.
- Destroy 시 Seoul targeted destroy를 생략하고 수동으로 `aws ec2 delete-vpc-peering-connection`을 쓸 수도 있으나, 이후 반드시 Seoul state rm을 해줘야 다음 apply가 깨끗하게 동작한다.

## 절대 묻지 않아도 되는 것 / 예외적으로 멈춰야 하는 것

- region 순서, `-auto-approve` 사용 여부, 위 표에 있는 트러블슈팅 적용 여부는 절대 묻지 않는다.
- 단, **코드에 정의되지 않은 리소스**(수동으로 콘솔에서 만든 것으로 추정되는 것)를 삭제해야 할 것 같은 상황이거나, RDS의 실제 데이터 손실(final snapshot 없이 삭제 등)이 코드 의도와 다르게 발생할 위험이 보이면 그때는 멈추고 알린다. 그 외에는 끝까지 진행한다.

## 보안

`tfstate`, `tfvars`, account ID, certificate ARN 등 민감값은 절대 git에 커밋하지 않는다. 저장소를 public으로 전환하기 전에는 git history scrub이 먼저 끝났는지 확인한다.
