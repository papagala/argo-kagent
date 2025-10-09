#!/bin/bash

# Simplified Kagent ArgoCD Setup Script
# Kind + ArgoCD setup for local development

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; exit 1; }

# Fixed Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_DIR="${SCRIPT_DIR}/argocd"
ENV_FILE="${SCRIPT_DIR}/.env"
ARGOCD_NAMESPACE="argocd"
KAGENT_NAMESPACE="kagent"

# Load environment variables
load_env_file() {
    [[ ! -f "$ENV_FILE" ]] && log_error ".env file not found! Create it from .env.template"
    
    log_info "Loading configuration from .env file..."
    set -a; source "$ENV_FILE"; set +a
    
    # Validate required variables
    [[ -z "$OPENAI_API_KEY" ]] && log_error "OPENAI_API_KEY is required in .env"
    
    # Set defaults for optional variables
    export KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kagent-demo}"
    export CA_BUNDLE_PATH="${CA_BUNDLE_PATH:-$HOME/.certs/ca-bundle.crt}"
    
    log_success "Configuration loaded"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    command -v kubectl &> /dev/null || log_error "kubectl not found"
    command -v argocd &> /dev/null || log_error "ArgoCD CLI not found. Install with: brew install argocd"
    command -v helm &> /dev/null || log_error "Helm not found. Install with: brew install helm"
    command -v kind &> /dev/null || log_error "Kind not found"
    command -v podman &> /dev/null || log_error "Podman not found"
    
    kubectl cluster-info &> /dev/null || log_error "Cannot connect to Kubernetes cluster"
    
    log_success "Prerequisites check passed"
}

# Fix certificates for Kind (only if needed)
fix_kind_certificates() {
    local initial_setup="$1"
    local ca_bundle_path="$CA_BUNDLE_PATH"
    
    # Skip if CA bundle path is not configured or doesn't exist
    [[ -z "$ca_bundle_path" || ! -f "$ca_bundle_path" ]] && {
        log_info "CA bundle not found at ${ca_bundle_path:-'(not configured)'} - skipping certificate fixes"
        log_info "To configure custom CA certificates, set CA_BUNDLE_PATH in your .env file"
        return 0
    }
    
    # Check if certificates are already applied by testing TLS connectivity
    if kubectl run cert-test --image=curlimages/curl --rm -it --restart=Never --quiet -- curl -s --connect-timeout 3 https://external-secrets.io/index.yaml >/dev/null 2>&1; then
        log_info "TLS certificates are working - skipping certificate fixes"
        return 0
    fi
    
    log_info "Applying certificate fixes for Kind cluster..."
    
    log_info "Copying CA bundle to Kind nodes..."
    local needs_restart=false
    for node in $(kind get nodes --name "${KIND_CLUSTER_NAME:-kagent-demo}"); do
        log_info "Processing node: $node"
        
        # Check if the certificate is already there and up to date
        if ! podman exec "$node" diff "$ca_bundle_path" "/usr/local/share/ca-certificates/ca-bundle.crt" >/dev/null 2>&1; then
            podman cp "$ca_bundle_path" "$node:/usr/local/share/ca-certificates/ca-bundle.crt"
            podman exec "$node" update-ca-certificates
            needs_restart=true
        else
            log_info "Certificates already up to date on $node"
        fi
    done
    
    if [[ "$needs_restart" == "true" ]]; then
        if [[ "$initial_setup" == "true" ]]; then
            log_info "Restarting containerd on nodes with updated certificates (--initial setup)..."
            for node in $(kind get nodes --name "${KIND_CLUSTER_NAME:-kagent-demo}"); do
                podman exec "$node" pkill -HUP containerd
            done
            
            log_info "Waiting for containerd to be ready..."
            sleep 5
        else
            log_info "Certificates updated but skipping containerd restart (use --initial to force restart)"
        fi
        
        # Wait for cluster to be accessible
        local retry_count=0
        while ! kubectl cluster-info &>/dev/null && [[ $retry_count -lt 30 ]]; do
            sleep 2; ((retry_count++))
        done
        
        log_success "Certificate fixes applied"
    else
        log_success "Certificate fixes not needed - already applied"
    fi
}

# Create secrets imperatively using kubectl and .env values
create_imperative_secrets() {
    log_info "Creating secrets imperatively using kubectl..."
    
    # Create kagent namespace
    kubectl create namespace "$KAGENT_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create OpenAI API key secret in kagent namespace
    log_info "Creating kagent-openai secret in $KAGENT_NAMESPACE namespace..."
    kubectl create secret generic kagent-openai \
        --from-literal=OPENAI_API_KEY="$OPENAI_API_KEY" \
        -n "$KAGENT_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create MCP secrets (used by MCP servers)
    log_info "Creating mcp-secrets in $KAGENT_NAMESPACE namespace..."
    kubectl create secret generic mcp-secrets \
        --from-literal=OPENAI_API_KEY="$OPENAI_API_KEY" \
        -n "$KAGENT_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Imperative secrets created successfully"
}

# Install ArgoCD
install_argocd() {
    log_info "Installing ArgoCD..."
    
    kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n "$ARGOCD_NAMESPACE" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    log_info "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n "$ARGOCD_NAMESPACE"
    
    log_success "ArgoCD installed"
}



# Deploy ArgoCD applications
deploy_applications() {
    log_info "Deploying ArgoCD applications..."
    
    kubectl apply -f "${ARGOCD_DIR}/kagent-project.yaml"
    sleep 2

    kubectl apply -f "${ARGOCD_DIR}/kagent-simple-app.yaml"
    kubectl apply -f "${ARGOCD_DIR}/mcp-sqlite-vec-app.yaml"
    
    log_success "ArgoCD applications deployed"
}

# Configure applications using ArgoCD CLI
configure_applications() {
    log_info "Configuring applications with ArgoCD CLI..."
    
    # Wait for all applications to be created
    log_info "Waiting for applications to be ready..."
    local apps=("kagent" "mcp-sqlite-vec")
    for app in "${apps[@]}"; do
        local retry_count=0
        while ! kubectl get application "$app" -n "$ARGOCD_NAMESPACE" &>/dev/null && [[ $retry_count -lt 60 ]]; do
            sleep 5; ((retry_count++))
            if [[ $((retry_count % 6)) -eq 0 ]]; then
                log_info "Still waiting for application $app... (${retry_count}/60)"
            fi
        done
        
        if ! kubectl get application "$app" -n "$ARGOCD_NAMESPACE" &>/dev/null; then
            log_error "Application $app not found after waiting"
        fi
    done
    
    # Start port-forward for ArgoCD with retry logic
    log_info "Starting ArgoCD port-forward..."
    
    # Kill any existing port-forward on 8080
    pkill -f "port-forward.*8080" 2>/dev/null || true
    sleep 2
    
    # Wait for ArgoCD server to be ready
    log_info "Waiting for ArgoCD server to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/argocd-server -n "$ARGOCD_NAMESPACE" || {
        log_warning "ArgoCD server not ready, but continuing..."
    }
    
    # Start port-forward with retry
    local pf_retry=0
    local port_forward_pid
    while [[ $pf_retry -lt 3 ]]; do
        kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" 8080:443 >/dev/null 2>&1 &
        port_forward_pid=$!
        echo $port_forward_pid > /tmp/argocd-port-forward.pid
        sleep 3
        
        # Verify port-forward is running
        if kill -0 $port_forward_pid 2>/dev/null; then
            log_success "ArgoCD port-forward started (PID: $port_forward_pid)"
            break
        else
            log_warning "Port-forward attempt $((pf_retry + 1)) failed, retrying..."
            ((pf_retry++))
            sleep 2
        fi
    done
    
    if [[ $pf_retry -eq 3 ]]; then
        log_warning "ArgoCD port-forward failed to start after 3 attempts"
        return 1
    fi
    
    # Get admin password and login
    local admin_password
    admin_password=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    log_success "ArgoCD accessible at: https://localhost:8080 (admin/$admin_password)"
    argocd login localhost:8080 --username admin --password "$admin_password" --insecure
    
    # Wait for applications to be fully ready (not in progress)
    log_info "Waiting for applications to be ready for configuration..."
    for app in "${apps[@]}"; do
        local retry_count=0
        while [[ $retry_count -lt 30 ]]; do
            local operation_state=$(argocd app get "$app" -o json 2>/dev/null | jq -r '.status.operationState.phase // "Unknown"' 2>/dev/null || echo "Unknown")
            if [[ "$operation_state" == "Succeeded" ]] || [[ "$operation_state" == "Unknown" ]] || [[ "$operation_state" == "null" ]]; then
                log_info "Application $app is ready for configuration"
                break
            fi
            log_info "Waiting for $app operation to complete (current: $operation_state)..."
            sleep 10; ((retry_count++))
        done
    done
    
    # No need to configure applications with parameters - External Secrets handles all secrets automatically!
    
    # Sync applications one by one, with retry logic
    for app in "${apps[@]}"; do
        log_info "Syncing $app application..."
        local sync_retry=0
        while [[ $sync_retry -lt 3 ]]; do
            if argocd app sync "$app" --timeout 300; then
                log_success "$app synced successfully"
                break
            else
                log_warning "Sync failed for $app, retrying in 10 seconds... (attempt $((sync_retry + 1))/3)"
                sleep 10
                ((sync_retry++))
            fi
        done
        
        if [[ $sync_retry -eq 3 ]]; then
            log_warning "Failed to sync $app after 3 attempts, continuing..."
        fi
        
        # Wait between syncs
        sleep 5
    done
    
    log_success "Applications configured and synced"
    
    # Store port-forward PID for cleanup
    echo $port_forward_pid > /tmp/argocd-port-forward.pid
}

# Function to test if a port-forward is actually working
test_port_forward() {
    local url="$1"
    local service_name="$2"
    local max_attempts=10
    local attempt=0
    
    log_info "Testing $service_name connectivity..."
    
    while [[ $attempt -lt $max_attempts ]]; do
        # Try multiple health check endpoints
        for endpoint in "/health" "/api/health" "/" ""; do
            local test_url="${url}${endpoint}"
            if curl -s --connect-timeout 2 --max-time 5 "$test_url" >/dev/null 2>&1; then
                log_success "$service_name is responding at: $url"
                return 0
            fi
        done
        
        ((attempt++))
        if [[ $attempt -lt $max_attempts ]]; then
            log_info "Attempt $attempt/$max_attempts - $service_name not responding yet, retrying in 2 seconds..."
            sleep 2
        fi
    done
    
    log_warning "$service_name port-forward appears to be running but not responding at: $url"
    log_info "This might be normal if the service is still starting up."
    return 1
}

# Wait for Kagent UI and setup port-forwards
setup_port_forwards() {
    log_info "Setting up port-forwards..."
    
    # ArgoCD is already running from configure_applications
    log_success "ArgoCD accessible at: https://localhost:8080"
    
    # Wait for Kagent UI to be ready
    log_info "Waiting for Kagent UI to be ready..."
    local retry_count=0
    while [[ $retry_count -lt 120 ]]; do  # 10 minutes max
        if kubectl get service kagent-ui -n "$KAGENT_NAMESPACE" &>/dev/null; then
            if kubectl get endpoints kagent-ui -n "$KAGENT_NAMESPACE" -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -q .; then
                log_success "Kagent UI service is ready!"
                break
            fi
        fi
        sleep 5; ((retry_count++))
        if [[ $((retry_count % 12)) -eq 0 ]]; then
            log_info "Still waiting for Kagent UI... ($((retry_count/12))/10 minutes)"
        fi
    done
    
    if [[ $retry_count -ge 120 ]]; then
        log_warning "Kagent UI not ready after 10 minutes"
    else
        # Start Kagent UI port-forward
        log_info "Starting Kagent UI port-forward..."
        
        # Kill any existing port-forward on 8090
        pkill -f "port-forward.*8090" 2>/dev/null || true
        sleep 1
        
        # Start new port-forward with explicit nohup to prevent it from being killed
        nohup kubectl port-forward svc/kagent-ui -n "$KAGENT_NAMESPACE" 8090:80 >/tmp/kagent-ui-pf.log 2>&1 &
        local ui_pf_pid=$!
        echo $ui_pf_pid > /tmp/kagent-ui-port-forward.pid
        sleep 3
        
        # Verify port-forward is working
        if kill -0 $ui_pf_pid 2>/dev/null; then
            log_success "Kagent UI port-forward started (PID: $ui_pf_pid)"
            
            # Test connectivity
            if test_port_forward "http://localhost:8090" "Kagent UI"; then
                log_success "✅ Kagent UI accessible at: http://localhost:8090"
            else
                log_info "Kagent UI port-forward started but service may still be initializing"
                log_info "📍 Try accessing http://localhost:8090 in a few minutes"
                log_info "📋 Check logs: tail -f /tmp/kagent-ui-pf.log"
            fi
        else
            log_warning "Failed to start Kagent UI port-forward"
            log_info "You can try manually: kubectl port-forward svc/kagent-ui -n kagent 8090:80"
        fi
    fi
}

# Show final info
show_final_info() {
    local admin_password
    admin_password=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    echo
    log_success "Setup Complete! 🎉"
    echo "=================================================="
    echo "🌐 Services:"
    echo "   ArgoCD:     https://localhost:8080"
    echo "   Kagent UI:  http://localhost:8090"
    echo
    echo "🔐 ArgoCD Credentials:"
    echo "   Username: admin"
    echo "   Password: $admin_password"
    echo
    echo "📱 Applications:"
    kubectl get applications -n "$ARGOCD_NAMESPACE" 2>/dev/null || true
    echo
    echo "📝 Next Steps:"
    echo "   1. Connect your Git repository in ArgoCD"
    echo "   2. Update application sources to point to your repo"
    echo "   3. Configure any additional secrets as needed"
    echo "=================================================="
}

# Teardown function
teardown() {
    log_info "🧹 Starting complete teardown..."
    
    # Show what will be removed
    echo
    log_info "📊 Current resources:"
    echo "  ArgoCD Applications:"
    kubectl get applications -n "$ARGOCD_NAMESPACE" 2>/dev/null | grep -E "(kagent|mcp-sqlite-vec)" || echo "    None found"
    echo "  Kagent Namespace:"
    kubectl get namespace "$KAGENT_NAMESPACE" 2>/dev/null | grep -v NAME || echo "    Not found"
    echo "  ArgoCD Project:"
    kubectl get appproject kagent -n "$ARGOCD_NAMESPACE" 2>/dev/null | grep -v NAME || echo "    Not found"
    echo
    
    # Confirm teardown
    log_warning "This will completely remove ALL Kagent resources and namespaces."
    echo "   ✅ Kagent namespace and all resources"
    echo "   ✅ ArgoCD applications (kagent, mcp-sqlite-vec)"
    echo "   ✅ Kagent ArgoCD project"
    echo "   ✅ All port-forwards"
    echo "   🔄 Container images will be kept for faster restart"
    echo
    read -p "❓ Are you sure you want to proceed? (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Teardown cancelled"
        return 0
    fi
    
    log_info "🔄 Killing port-forwards..."
    # Kill port-forwards
    [[ -f /tmp/argocd-port-forward.pid ]] && kill $(cat /tmp/argocd-port-forward.pid) 2>/dev/null || true
    [[ -f /tmp/kagent-ui-port-forward.pid ]] && kill $(cat /tmp/kagent-ui-port-forward.pid) 2>/dev/null || true
    pkill -f "port-forward.*8080" 2>/dev/null || true
    pkill -f "port-forward.*8090" 2>/dev/null || true
    rm -f /tmp/argocd-port-forward.pid /tmp/kagent-ui-port-forward.pid /tmp/kagent-ui-pf.log
    log_success "Port-forwards killed"
    
    log_info "🗑️  Removing ArgoCD applications..."
    # Remove applications with wait to ensure proper cleanup
    local apps=("kagent" "mcp-sqlite-vec")
    for app in "${apps[@]}"; do
        if kubectl get application "$app" -n "$ARGOCD_NAMESPACE" &>/dev/null; then
            log_info "  Removing application: $app"
            kubectl delete application "$app" -n "$ARGOCD_NAMESPACE" --wait=false --ignore-not-found=true
        fi
    done
    
    # Wait a bit for applications to start deletion
    sleep 3
    
    log_info "🏗️  Forcefully removing Kagent namespace..."
    # Force delete the namespace completely
    if kubectl get namespace "$KAGENT_NAMESPACE" &>/dev/null; then
        # First try graceful deletion
        kubectl delete namespace "$KAGENT_NAMESPACE" --timeout=30s 2>/dev/null || {
            log_warning "Graceful deletion failed, forcing removal..."
            
            # Get all resources in the namespace and delete them
            kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -n "$KAGENT_NAMESPACE" 2>/dev/null || true
            
            # Force delete by removing finalizers
            kubectl get namespace "$KAGENT_NAMESPACE" -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/$KAGENT_NAMESPACE/finalize" -f - 2>/dev/null || true
            
            # Delete the namespace forcefully
            kubectl delete namespace "$KAGENT_NAMESPACE" --force --grace-period=0 2>/dev/null || true
        }
        
        # Wait for namespace to be completely gone
        local retry_count=0
        while kubectl get namespace "$KAGENT_NAMESPACE" &>/dev/null && [[ $retry_count -lt 30 ]]; do
            log_info "  Waiting for namespace deletion... ($retry_count/30)"
            sleep 2
            ((retry_count++))
        done
        
        if kubectl get namespace "$KAGENT_NAMESPACE" &>/dev/null; then
            log_warning "Namespace still exists but continuing..."
        else
            log_success "Kagent namespace completely removed"
        fi
    else
        log_info "Kagent namespace already removed"
    fi
    
    log_info "🔐 Removing secrets and ArgoCD project..."
    # Remove imperative secrets
    kubectl delete secret kagent-openai -n "$KAGENT_NAMESPACE" --ignore-not-found=true
    kubectl delete secret mcp-secrets -n "$KAGENT_NAMESPACE" --ignore-not-found=true
    
    # Remove the ArgoCD project
    kubectl delete appproject kagent -n "$ARGOCD_NAMESPACE" --ignore-not-found=true
    
    # Optional: Remove AWS secrets (commented out for safety)
    # log_info "To remove AWS secrets, run:"
    # echo "  aws secretsmanager delete-secret --secret-id kagent/openai-api-key --force-delete-without-recovery"
    
    log_info "🧽 Cleaning up temporary files..."
    rm -f /tmp/*-port-forward.pid /tmp/kagent-ui-pf.log
    
    echo
    log_success "🎉 Complete teardown finished!"
    echo "=================================================="
    echo "✅ Removed:"
    echo "   - Kagent namespace (completely)"
    echo "   - All ArgoCD applications"  
    echo "   - Kagent ArgoCD project"
    echo "   - All port-forwards"
    echo
    echo "🔄 Preserved:"
    echo "   - Container images in Kind cluster"
    echo "   - ArgoCD installation"
    echo "   - Kind cluster"
    echo
    echo "🚀 Next steps:"
    echo "   - Run './setup-kagent.sh' to redeploy quickly"
    echo "   - Images are cached for faster startup"
    echo "=================================================="
}

# Show port-forward status
show_status() {
    echo "🔍 Port-Forward Status:"
    echo "======================="
    
    # Check ArgoCD port-forward
    if [[ -f /tmp/argocd-port-forward.pid ]] && kill -0 $(cat /tmp/argocd-port-forward.pid) 2>/dev/null; then
        echo "✅ ArgoCD: https://localhost:8080 (PID: $(cat /tmp/argocd-port-forward.pid))"
    else
        echo "❌ ArgoCD: Not running"
        echo "   Start with: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    fi
    
    # Check Kagent UI port-forward
    if [[ -f /tmp/kagent-ui-port-forward.pid ]] && kill -0 $(cat /tmp/kagent-ui-port-forward.pid) 2>/dev/null; then
        echo "✅ Kagent UI: http://localhost:8090 (PID: $(cat /tmp/kagent-ui-port-forward.pid))"
        
        # Test connectivity
        if curl -s --connect-timeout 2 http://localhost:8090 >/dev/null 2>&1; then
            echo "   Status: Responding ✅"
        else
            echo "   Status: Not responding (service may be starting) ⏳"
        fi
    else
        echo "❌ Kagent UI: Not running"
        echo "   Start with: kubectl port-forward svc/kagent-ui -n kagent 8090:80"
    fi
    
    echo
    echo "🔧 Manual port-forward commands:"
    echo "  ArgoCD:     kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "  Kagent UI:  kubectl port-forward svc/kagent-ui -n kagent 8090:80"
}

# Show usage
show_usage() {
    echo "Simplified Kagent Setup Script"
    echo
    echo "USAGE:"
    echo "  $0 [OPTIONS]"
    echo
    echo "OPTIONS:"
    echo "  --skip-argocd     Skip ArgoCD installation"
    echo "  --initial         Force containerd restart during certificate fixes"
    echo "  --teardown        Remove all Kagent resources"
    echo "  --status          Show port-forward status"
    echo "  --help            Show this help"
    echo
    echo "SETUP:"
    echo "  1. Create .env file with all required variables (see .env.template)"
    echo "  2. Run: ./setup-kagent.sh"
    echo
    echo "REQUIREMENTS:"
    echo "  - Kind cluster running"
    echo "  - Helm 3.x installed" 
    echo "  - OPENAI_API_KEY set in .env file"
    echo "  - Optional: CA_BUNDLE_PATH for custom certificates"
}

# Main function
main() {
    local skip_argocd=false
    local initial_setup=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-argocd) skip_argocd=true; shift ;;
            --initial) initial_setup=true; shift ;;
            --teardown) load_env_file; teardown; exit 0 ;;
            --status) show_status; exit 0 ;;
            --help) show_usage; exit 0 ;;
            *) log_error "Unknown option: $1" ;;
        esac
    done
    
    # Main setup flow
    load_env_file
    check_prerequisites
    fix_kind_certificates "$initial_setup"
    
    # Install ArgoCD first (we need ArgoCD to exist before creating ArgoCD Application CRs)
    if [[ "$skip_argocd" == "false" ]]; then
        if ! kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
            install_argocd
        else
            log_info "ArgoCD already installed"
        fi
    fi

    # Create secrets imperatively using kubectl and .env values
    create_imperative_secrets
    
    deploy_applications
    configure_applications
    setup_port_forwards
    show_final_info
    
    echo
    echo "💡 Helpful commands:"
    echo "  kubectl get applications -n argocd"
    echo "  kubectl get all -n kagent"
    echo "  kubectl get secrets -n kagent"
    echo "  argocd app list"
}

# Cleanup on interruption (not normal exit)
cleanup_on_interrupt() {
    log_warning "Script interrupted, cleaning up background processes..."
    
    # Kill port-forwards using PID files
    [[ -f /tmp/argocd-port-forward.pid ]] && kill $(cat /tmp/argocd-port-forward.pid) 2>/dev/null || true
    [[ -f /tmp/kagent-ui-port-forward.pid ]] && kill $(cat /tmp/kagent-ui-port-forward.pid) 2>/dev/null || true
    
    # Kill any remaining port-forwards
    pkill -f "port-forward.*8080" 2>/dev/null || true
    pkill -f "port-forward.*8090" 2>/dev/null || true
    
    # Clean up PID files
    rm -f /tmp/argocd-port-forward.pid /tmp/kagent-ui-port-forward.pid /tmp/kagent-ui-pf.log
    
    exit 1
}

# Only cleanup on interruption, not normal exit
trap 'cleanup_on_interrupt' SIGINT SIGTERM

# Run main if script is executed directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"