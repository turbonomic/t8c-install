provider "helm" {
  kubernetes {
    config_path = "${var.kubeconfig}"
  }
}

resource "helm_release" "xl" {
  chart     = "../operator/helm-charts/xl"
  name      = "${var.name}"
  namespace = "${var.namespace}"

  set {
    name  = "global.tag"
    value = "${var.tag}"
  }

  set {
    name  = "global.externalIP"
    value = "${var.externalIP}"
  }

  # Monitoring
  set {
    name  = "grafana.enabled"
    value = "${var.grafana ? true : false}"
  }

  set {
    name  = "prometheus.enabled"
    value = "${var.prometheus ? true : false}"
  }

  # Logging
  set {
    name  = "global.elk"
    value = "${var.elk ? true : false}"
  }

  # Medation
  set {
    name  = "actionscript.enabled"
    value = "${var.actionscript ? true : false}"
  }

  set {
    name  = "aix.enabled"
    value = "${var.aix ? true : false}"
  }

  set {
    name  = "appdynamics.enabled"
    value = "${var.appdynamics ? true : false}"
  }

  set {
    name  = "aws.enabled"
    value = "${var.aws ? true : false}"
  }

  set {
    name  = "awsbilling.enabled"
    value = "${var.awsbilling ? true : false}"
  }

  set {
    name  = "awscost.enabled"
    value = "${var.awscost? true : false}"
  }

  set {
    name  = "awslambda.enabled"
    value = "${var.awslambda ? true : false}"
  }

  set {
    name  = "azure.enabled"
    value = "${var.azure ? true : false}"
  }

  set {
    name  = "azurecost.enabled"
    value = "${var.azurecost ? true : false}"
  }

  set {
    name  = "azurevolumes.enabled"
    value = "${var.azurevolumes ? true : false}"
  }

  set {
    name  = "cloudfoundry.enabled"
    value = "${var.cloudfoundry ? true : false}"
  }

  set {
    name  = "compellent.enabled"
    value = "${var.compellent ? true : false}"
  }

  set {
    name  = "dynatrace.enabled"
    value = "${var.dynatrace ? true : false}"
  }

  set {
    name  = "hpe3par.enabled"
    value = "${var.hpe3par ? true : false}"
  }

  set {
    name  = "hds.enabled"
    value = "${var.hds ? true : false}"
  }

  set {
    name  = "hyperflex.enabled"
    value = "${var.hyperflex ? true : false}"
  }

  set {
    name  = "hyperv.enabled"
    value = "${var.hyperv ? true : false}"
  }

  set {
    name  = "istio.enabled"
    value = "${var.istio ? true : false}"
  }

  set {
    name  = "mediation-actionstream-kafka.enabled"
    value = "${var.mediation-actionstream-kafka ? true : false}"
  }

  set {
    name  = "mssql.enabled"
    value = "${var.mssql ? true : false}"
  }

  set {
    name  = "mysql.enabled"
    value = "${var.mysql ? true : false}"
  }

  set {
    name  = "oracle.enabled"
    value = "${var.oracle ? true : false}"
  }

  set {
    name  = "tomcat.enabled"
    value = "${var.tomcat ? true : false}"
  }

  set {
    name  = "jvm.enabled"
    value = "${var.jvm ? true : false}"
  }

  set {
    name  = "netapp.enabled"
    value = "${var.netapp ? true : false}"
  }

  set {
    name  = "nutanix.enabled"
    value = "${var.nutanix ? true : false}"
  }

  set {
    name  = "netflow.enabled"
    value = "${var.netflow ? true : false}"
  }

  set {
    name  = "oneview.enabled"
    value = "${var.oneview ? true : false}"
  }

  set {
    name  = "openstack.enabled"
    value = "${var.openstack ? true : false}"
  }

  set {
    name  = "pivotal.enabled"
    value = "${var.pivotal ? true : false}"
  }

  set {
    name  = "pure.enabled"
    value = "${var.pure ? true : false}"
  }

  set {
    name  = "rhv.enabled"
    value = "${var.rhv ? true : false}"
  }

  set {
    name  = "scaleio.enabled"
    value = "${var.scaleio ? true : false}"
  }

  set {
    name  = "snmp.enabled"
    value = "${var.snmp ? true : false}"
  }

  set {
    name  = "tetration.enabled"
    value = "${var.tetration ? true : false}"
  }

  set {
    name  = "ucs.enabled"
    value = "${var.ucs ? true : false}"
  }

  set {
    name  = "ucsdirector.enabled"
    value = "${var.ucsdirector ? true : false}"
  }

  set {
    name  = "vcd.enabled"
    value = "${var.vcd ? true : false}"
  }

  set {
    name  = "vcenter.enabled"
    value = "${var.vcenter ? true : false}"
  }

  set {
    name  = "vcenterbrowsing.enabled"
    value = "${var.vcenterbrowsing ? true : false}"
  }

  set {
    name  = "vmax.enabled"
    value = "${var.vmax ? true : false}"
  }

  set {
    name  = "vmm.enabled"
    value = "${var.vmm ? true : false}"
  }

  set {
    name  = "vplex.enabled"
    value = "${var.vplex ? true : false}"
  }

  set {
    name  = "wmi.enabled"
    value = "${var.wmi ? true : false}"
  }

  set {
    name  = "xtremio.enabled"
    value = "${var.xtremio ? true : false}"
  }

  set {
      name  = "udt.enabled"
      value = "${var.udt ? true : false}"
    }
}
