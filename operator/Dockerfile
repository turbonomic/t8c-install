FROM quay.io/operator-framework/helm-operator:v1.25
MAINTAINER Endre Sara <endre.sara@turbonomic.com>

# Required OpenShift Labels
LABEL name="t8c-operator" \
      vendor="Turbonomic" \
      version="42" \
      release="21" \
      summary="Turbonomic Platform Operator" \
      description="Turbonomic Workload Automation for Multicloud simultaneously optimizes performance, compliance, and cost in real-time. Workloads are precisely resourced, automatically, to perform while satisfying business constraints." \
### Required labels above - recommended below
      url="https://www.turbonomic.com" \
      run='docker run -tdi --name ${NAME} turbonomic/t8c-operator:42.21' \
      io.k8s.description="Turbonomic Workload Automation Platform simultaneously optimizes performance, compliance, and cost in real-time. Workloads are precisely resourced, automatically, to perform while satisfying business constraints.  " \
      io.k8s.display-name="Turbonomic Platform Operator" \
      io.openshift.expose-services="" \
      io.openshift.tags="turbonomic, Workload Automation Platform"

ENV HOME=/opt/helm
# Required Licenses
COPY licenses /licenses

COPY watches.yaml ${HOME}/watches.yaml
COPY helm-charts/ ${HOME}/helm-charts/
