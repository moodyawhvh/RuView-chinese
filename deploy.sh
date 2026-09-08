#!/bin/bash

# WiFi-DensePose 部署脚本
# 本脚本编排 WiFi-DensePose 基础设施的完整部署流程

set -euo pipefail

# 配置区:目录、项目名与可被环境变量覆盖的默认值
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="wifi-densepose"
ENVIRONMENT="${ENVIRONMENT:-production}"
AWS_REGION="${AWS_REGION:-us-west-2}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-~/.kube/config}"

# 输出配色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色(复位)

# 日志函数:信息 / 成功 / 警告 / 错误 四级
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 前置条件检查:工具、AWS 凭据、Docker 守护进程
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    # 检查必需的 CLI 工具是否全部可用
    for tool in aws kubectl helm terraform docker; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again."
        exit 1
    fi

    # 校验 AWS 凭据有效性(STS 调用方身份)
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        log_info "Please configure AWS credentials using 'aws configure' or environment variables"
        exit 1
    fi

    # 校验 Docker 守护进程是否在运行
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        log_info "Please start Docker daemon and try again"
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

# 用 Terraform 部署基础设施
deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."

    cd "${SCRIPT_DIR}/terraform"

    # 初始化 Terraform(拉取 provider 与后端)
    log_info "Initializing Terraform..."
    terraform init

    # 生成部署计划(不入库的 tfplan)
    log_info "Planning Terraform deployment..."
    terraform plan -var="environment=${ENVIRONMENT}" -var="aws_region=${AWS_REGION}" -out=tfplan

    # 应用部署计划
    log_info "Applying Terraform deployment..."
    terraform apply tfplan

    # 刷新本地 kubeconfig,指向新拉的 EKS 集群
    log_info "Updating kubeconfig..."
    aws eks update-kubeconfig --region "${AWS_REGION}" --name "${PROJECT_NAME}-cluster"

    log_success "Infrastructure deployed successfully"
    cd "${SCRIPT_DIR}"
}

# 部署 Kubernetes 资源
deploy_kubernetes() {
    log_info "Deploying Kubernetes resources..."

    # 创建命名空间
    log_info "Creating namespaces..."
    kubectl apply -f k8s/namespace.yaml

    # 部署 ConfigMap 与 Secret
    log_info "Deploying ConfigMaps and Secrets..."
    kubectl apply -f k8s/configmap.yaml
    kubectl apply -f k8s/secrets.yaml

    # 部署应用:工作负载、服务、入口、水平扩缩容
    log_info "Deploying application..."
    kubectl apply -f k8s/deployment.yaml
    kubectl apply -f k8s/service.yaml
    kubectl apply -f k8s/ingress.yaml
    kubectl apply -f k8s/hpa.yaml

    # 等待部署达到可用状态(最长 300 秒)
    log_info "Waiting for deployment to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/wifi-densepose -n wifi-densepose

    log_success "Kubernetes resources deployed successfully"
}

# 部署监控栈
deploy_monitoring() {
    log_info "Deploying monitoring stack..."

    # 添加 Helm 仓库并刷新索引
    log_info "Adding Helm repositories..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update

    # 创建 monitoring 命名空间(幂等:不存在则创建)
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

    # 部署 Prometheus(kube-prometheus-stack,等待就绪)
    log_info "Deploying Prometheus..."
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --values monitoring/prometheus-values.yaml \
        --wait

    # 以 ConfigMap 方式注入 Grafana 仪表盘
    log_info "Deploying Grafana dashboard..."
    kubectl create configmap grafana-dashboard \
        --from-file=monitoring/grafana-dashboard.json \
        --namespace monitoring \
        --dry-run=client -o yaml | kubectl apply -f -

    # 部署 Fluentd 日志采集配置
    log_info "Deploying Fluentd..."
    kubectl apply -f logging/fluentd-config.yml

    log_success "Monitoring stack deployed successfully"
}

# 构建并推送 Docker 镜像
build_and_push_images() {
    log_info "Building and pushing Docker images..."

    # 获取 ECR 登录令牌并登录账号对应的 ECR 注册表
    aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${AWS_REGION}.amazonaws.com"

    # 构建应用镜像(latest 标签)
    log_info "Building application image..."
    docker build -t "${PROJECT_NAME}:latest" .

    # 打上 latest 与 git 短 SHA 双标签,推送到 ECR
    local ecr_repo="$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}"
    docker tag "${PROJECT_NAME}:latest" "${ecr_repo}:latest"
    docker tag "${PROJECT_NAME}:latest" "${ecr_repo}:$(git rev-parse --short HEAD)"

    log_info "Pushing images to ECR..."
    docker push "${ecr_repo}:latest"
    docker push "${ecr_repo}:$(git rev-parse --short HEAD)"

    log_success "Docker images built and pushed successfully"
}

# 运行健康检查
run_health_checks() {
    log_info "Running health checks..."

    # 检查 Pod 状态
    log_info "Checking pod status..."
    kubectl get pods -n wifi-densepose

    # 检查服务端点
    log_info "Checking service endpoints..."
    kubectl get endpoints -n wifi-densepose

    # 检查入口
    log_info "Checking ingress..."
    kubectl get ingress -n wifi-densepose

    # 探测应用 /health 端点
    local app_url=$(kubectl get ingress wifi-densepose-ingress -n wifi-densepose -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if [ -n "$app_url" ]; then
        log_info "Testing application health endpoint..."
        if curl -f "http://${app_url}/health" &> /dev/null; then
            log_success "Application health check passed"
        else
            log_warning "Application health check failed"
        fi
    else
        log_warning "Ingress URL not available yet"
    fi

    log_success "Health checks completed"
}

# 配置 CI/CD
setup_cicd() {
    log_info "Setting up CI/CD pipelines..."

    # 检出的是 GitHub 仓库时,提示需要手工配置的 Actions secrets
    if [ -d ".git" ] && git remote get-url origin | grep -q "github.com"; then
        log_info "GitHub repository detected"
        log_info "Please configure the following secrets in your GitHub repository:"
        echo "  - AWS_ACCESS_KEY_ID"
        echo "  - AWS_SECRET_ACCESS_KEY"
        echo "  - KUBE_CONFIG_DATA"
        echo "  - ECR_REPOSITORY"
    fi

    # 校验 CI/CD 配置文件是否存在
    if [ -f ".github/workflows/ci.yml" ]; then
        log_success "GitHub Actions CI workflow found"
    fi

    if [ -f ".github/workflows/cd.yml" ]; then
        log_success "GitHub Actions CD workflow found"
    fi

    if [ -f ".gitlab-ci.yml" ]; then
        log_success "GitLab CI configuration found"
    fi

    log_success "CI/CD setup completed"
}

# 清理函数:删除 Terraform 计划文件等临时产物
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -f terraform/tfplan
}

# 主部署入口
main() {
    log_info "Starting WiFi-DensePose deployment..."
    log_info "Environment: ${ENVIRONMENT}"
    log_info "AWS Region: ${AWS_REGION}"

    # 注册退出钩子:无论成功失败都执行清理
    trap cleanup EXIT

    # 依次执行部署步骤
    check_prerequisites

    # 按第一个参数选择部署目标,默认 all(全流程)
    case "${1:-all}" in
        "infrastructure")
            deploy_infrastructure
            ;;
        "kubernetes")
            deploy_kubernetes
            ;;
        "monitoring")
            deploy_monitoring
            ;;
        "images")
            build_and_push_images
            ;;
        "health")
            run_health_checks
            ;;
        "cicd")
            setup_cicd
            ;;
        "all")
            deploy_infrastructure
            build_and_push_images
            deploy_kubernetes
            deploy_monitoring
            setup_cicd
            run_health_checks
            ;;
        *)
            log_error "Unknown deployment target: $1"
            log_info "Usage: $0 [infrastructure|kubernetes|monitoring|images|health|cicd|all]"
            exit 1
            ;;
    esac

    log_success "WiFi-DensePose deployment completed successfully!"

    # 输出常用运维命令
    echo ""
    log_info "Useful commands:"
    echo "  kubectl get pods -n wifi-densepose"
    echo "  kubectl logs -f deployment/wifi-densepose -n wifi-densepose"
    echo "  kubectl port-forward svc/grafana 3000:80 -n monitoring"
    echo "  kubectl port-forward svc/prometheus-server 9090:80 -n monitoring"
    echo ""

    # 输出访问地址:应用入口与 Grafana
    local ingress_url=$(kubectl get ingress wifi-densepose-ingress -n wifi-densepose -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Not available yet")
    log_info "Application URL: http://${ingress_url}"

    local grafana_url=$(kubectl get ingress grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Use port-forward")
    log_info "Grafana URL: http://${grafana_url}"
}

# 携带全部参数运行主函数
main "$@"
