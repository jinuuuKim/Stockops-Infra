# CLAUDE.md — Stockops-Infra

> 이 파일을 `C:\KJW\Team_Project\Stockops-Infra\CLAUDE.md` 에 저장하세요.
> Claude Code가 이 디렉터리(또는 하위 `seoul/`, `ohio/`, `global/`)에서 세션을 시작할 때마다 자동으로 로드됩니다.

## 이 저장소

StockOps 멀티리전 AWS 인프라(Terraform IaC). 3개의 독립된 state로 분리되어 있음:
`infra/seoul`(primary), `infra/ohio`(failover), `infra/global`(Route53/ACM/Global Accelerator).
global은 seoul/ohio의 output을 `terraform_remote_state`로 참조하므로 **순서에 의존성이 있음**.

## 자동 실행 원칙 (가장 중요)

- terraform plan/apply/destroy를 실행할 때 **반드시 `-auto-approve`를 붙인다.** 이게 없으면 terraform이 콘솔에서 "yes"를 기다리며 멈춘다 — Claude Code의 권한 프롬프트와는 별개의 문제이니 항상 플래그로 해결한다.
- 작업 시작 전 "진행해도 될까요?", "destroy 할까요?" 같은 확인을 사용자에게 구하지 않는다. 사용자가 이미 apply/destroy를 요청했다면 끝까지 실행한다.
- 중간 단계마다 보고하지 않는다. 전체 작업(예: 3개 region apply, 또는 전체 destroy)이 끝난 뒤 결과를 한 번에 간결히 요약 보고한다. 진행 중 발생한 에러와 그 해결 방법은 요약에 포함한다.
- 에러가 발생하면 먼저 아래 "알려진 트러블슈팅 패턴"에서 해당하는 항목을 찾아 직접 해결을 시도한다. 사용자에게 "어떻게 할까요?"라고 묻지 않는다. 패턴에 없는 새로운 에러라면 원인을 분석하고 합리적인 해결책을 직접 적용한 뒤, 무엇을 왜 했는지 사후 보고한다.

## Apply / Destroy 순서

- **Apply**: Seoul → Ohio → Global (global이 seoul/ohio의 ALB ARN 등을 remote state로 참조하기 때문)
- **Destroy**: Global → Ohio → Seoul (apply의 역순. global이 참조하는 리소스를 먼저 없는 상태로 만들면 안 되고, Ohio의 RDS Read Replica가 Seoul의 RDS Primary를 참조하므로 Replica를 먼저 지워야 함)
- 각 region 디렉터리에서 독립적으로 `terraform destroy -auto-approve` / `terraform apply -auto-approve` 실행

## 알려진 트러블슈팅 패턴 (자동 해결)

| 증상 | 해결 |
|---|---|
| IoT policy/Thing이 연결된 상태에서 destroy 실패 | destroy 전에 AWS CLI로 IoT policy/Thing을 인증서에서 먼저 detach |
| PowerShell에서 ECR 로그인 시 토큰 깨짐 | `aws ecr get-login-password \| Out-File -Encoding ascii` 후 그 파일을 `docker login`에 파이프 (파이프 연산자로 직접 넘기면 인코딩이 깨짐) |
| RDS parameter group 삭제가 막힘 | 해당 parameter group을 쓰는 RDS 인스턴스가 아직 살아있는지 확인, 인스턴스 삭제 완료 후 재시도 |
| ECR repo가 destroy 대상에 포함되어 있음 | ECR은 `data` source로 유지해야 destroy cycle에서 안전 — `resource`로 되어있다면 `data`로 전환 |
| `terraform destroy` 중 ArgoCD CRD 관련 kubectl 에러 | 무시 가능, destroy를 막지 않음 |
| `helm_release.argocd`가 "Still destroying..."로 멈춤 | 1) `kubectl get applications -n argocd` 확인 2) 각 Application에 `kubectl patch application <name> -n argocd --type merge -p '{"metadata":{"finalizers":null}}'` 로 finalizer 제거 3) 그래도 안 풀리면 `terraform state rm helm_release.argocd` + `kubectl delete namespace argocd --grace-period=0 --force` |
| subnet destroy가 "Still destroying..."로 멈춤 | `aws ec2 describe-network-interfaces --filters "Name=subnet-id,Values=<id>"`로 ENI 확인 → `available` 상태면 `aws ec2 delete-network-interface`로 직접 삭제 → `in-use`면 원인 리소스(ELB/Lambda/EKS 노드) 먼저 정리 |
| IoT 인증서가 `var.iot_certificate_arn`으로 참조됨 | destroy cycle을 살리기 위한 의도된 설계이므로 변경하지 않음 |

새로운 패턴을 발견하면 이 표에 추가해서 다음 세션에도 재사용한다.

## 절대 묻지 않아도 되는 것 / 예외적으로 멈춰야 하는 것

- region 순서, `-auto-approve` 사용 여부, 위 표에 있는 트러블슈팅 적용 여부는 절대 묻지 않는다.
- 단, **코드에 정의되지 않은 리소스**(수동으로 콘솔에서 만든 것으로 추정되는 것)를 삭제해야 할 것 같은 상황이거나, RDS의 실제 데이터 손실(final snapshot 없이 삭제 등)이 코드 의도와 다르게 발생할 위험이 보이면 그때는 멈추고 알린다. 그 외에는 끝까지 진행한다.

## 보안

`tfstate`, `tfvars`, account ID, certificate ARN 등 민감값은 절대 git에 커밋하지 않는다. 저장소를 public으로 전환하기 전에는 git history scrub이 먼저 끝났는지 확인한다.
