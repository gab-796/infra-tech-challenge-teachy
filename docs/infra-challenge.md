# Infrastructure Technical Challenge - Kubernetes & Observability

## Challenge Overview

This technical challenge is designed to assess your expertise in infrastructure automation, container orchestration, and observability stack implementation. You will be required to provision a complete local Kubernetes environment with a full observability solution, entirely managed through Infrastructure as Code.

## Core Requirements

### 1. Local Kubernetes Cluster (Terraform-managed)

- **Provision a local Kubernetes cluster** using Terraform (kind, k3s, or minikube)
- **Cluster specifications:** At least 1 control plane node and 2 worker nodes
- **Network configuration:** Configure proper networking between nodes
- **Storage:** Configure persistent volume support

### 2. Observability Stack (Full Terraform Implementation)

- **Prometheus:** Deploy and configure Prometheus for metrics collection
- **Loki:** Deploy Loki for log aggregation and querying
- **Tempo:** Deploy Tempo for distributed tracing
- **Grafana:** Deploy Grafana with pre-configured dashboards for all three data sources
- **Integration:** Ensure all components are properly integrated and communicating

### 3. Sample Application

- **Deploy a sample microservices application** (at least 2-3 services)
- **Instrumentation:** Application must emit metrics, logs, and traces

## Additional Suggested Components

### Security & Access Control

- **RBAC configuration:** Implement proper role-based access control
- **Network policies:** Define and implement Kubernetes network policies
- **Secrets management:** Use Kubernetes secrets or external solutions (Vault, Sealed Secrets)

### High Availability & Resilience

- **Pod disruption budgets:** Configure PDBs for critical services
- **Resource limits:** Define CPU and memory requests/limits for all workloads
- **Health checks:** Implement readiness and liveness probes
- **Auto-scaling:** Configure Horizontal Pod Autoscaler (HPA) for the sample application

### Monitoring Enhancements

- **AlertManager:** Configure alerting rules and notification channels
- **Custom dashboards:** Create custom Grafana dashboards showing cluster health and application metrics
- **SLO/SLI tracking:** Define and track Service Level Objectives
- **Cost monitoring:** Implement resource usage and cost tracking dashboards

### Infrastructure Best Practices

- **Terraform modules:** Organize code into reusable modules
- **Remote state:** Configure remote state backend (local S3-compatible solution)
- **Variable management:** Use terraform.tfvars and environment-specific configurations
- **Documentation:** Include comprehensive README with architecture diagrams

### Service Mesh

- **Istio or Linkerd:** Deploy a service mesh for advanced traffic management and observability
- **mTLS:** Enable mutual TLS between services for secure communication
- **Traffic management:** Implement canary deployments, circuit breaking, and retry policies
- **Distributed tracing integration:** Configure service mesh to export traces to Tempo
- **Service mesh observability:** Create Grafana dashboards for service mesh metrics (latency, success rate, traffic flow)

## Deliverables

- [ ]  **Git repository** with all Terraform code and configuration files
- [ ]  **README.md** with clear setup instructions and architecture overview
- [ ]  **Architecture diagram** showing component relationships
- [ ]  **Working cluster** that can be deployed with a single command
- [ ]  **Documentation** of any design decisions or trade-offs made

## Evaluation Criteria

- **Functionality:** All components work as expected and are properly integrated
- **Code quality:** Clean, well-organized, and idiomatic Terraform code
- **Best practices:** Adherence to infrastructure and Kubernetes best practices
- **Documentation:** Clear and comprehensive documentation
- **Observability:** Effective implementation of metrics, logs, and traces
- **Automation:** High degree of automation with minimal manual steps
- **Bonus points:** Implementation of suggested additional components

## Time Allocation

Expected completion time: **2 days**

## Submission Instructions

1. Push your IaC code to a public Git repository (GitHub, GitLab, etc.)
2. Ensure all documentation is included in the repository
3. Send the repository link along with any additional notes
4. Be prepared to discuss your implementation choices in a follow-up technical interview

## Resources & References

- [Terraform Documentation](https://www.terraform.io/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/home/)
- [Grafana Labs Documentation](https://grafana.com/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)

<aside>
💡 **Note:** Feel free to ask clarifying questions before starting. We're interested in seeing your problem-solving approach and technical decision-making process.

</aside>