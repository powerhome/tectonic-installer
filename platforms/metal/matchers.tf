module "container_linux" {
  source = "../../modules/container_linux"

  release_channel = "${var.tectonic_container_linux_channel}"
  release_version = "${var.tectonic_container_linux_version}"
}

// Install CoreOS to disk
resource "matchbox_group" "coreos_install" {
  count   = "${length(var.tectonic_metal_controller_names) + length(var.tectonic_metal_worker_names)}"
  name    = "${format("coreos-install-%s", element(concat(var.tectonic_metal_controller_names, var.tectonic_metal_worker_names), count.index))}"
  profile = "${matchbox_profile.coreos_install.name}"

  selector {
    mac = "${element(concat(var.tectonic_metal_controller_macs, var.tectonic_metal_worker_macs), count.index)}"
  }

  metadata {
    coreos_channel     = "${var.tectonic_container_linux_channel}"
    coreos_version     = "${module.container_linux.version}"
    ignition_endpoint  = "${var.tectonic_metal_matchbox_http_url}/ignition"
    baseurl            = "${var.tectonic_metal_matchbox_http_url}/assets/coreos"
    ssh_authorized_key = "${var.tectonic_ssh_authorized_key}"
  }
}

// DO NOT PLACE SECRETS IN USER-DATA

module "ignition_masters" {
  source = "../../modules/ignition"

  bootstrap_upgrade_cl      = "${var.tectonic_bootstrap_upgrade_cl}"
  cluster_name              = "${var.tectonic_cluster_name}"
  container_images          = "${var.tectonic_container_images}"
  custom_ca_cert_pem_list   = "${var.tectonic_custom_ca_pem_list}"
  etcd_advertise_name_list  = "${var.tectonic_metal_controller_domains}"
  etcd_ca_cert_pem          = "${module.etcd_certs.etcd_ca_crt_pem}"
  etcd_count                = "${length(var.tectonic_metal_controller_names)}"
  etcd_initial_cluster_list = "${var.tectonic_metal_controller_domains}"
  image_re                  = "${var.tectonic_image_re}"
  ingress_ca_cert_pem       = "${module.ingress_certs.ca_cert_pem}"
  kube_ca_cert_pem          = "${module.kube_certs.ca_cert_pem}"
  kube_dns_service_ip       = "${module.bootkube.kube_dns_service_ip}"
  kubelet_cni_bin_dir       = "${var.tectonic_networking == "calico" || var.tectonic_networking == "canal" ? "/var/lib/cni/bin" : "" }"
  kubelet_debug_config      = "${var.tectonic_kubelet_debug_config}"
  kubelet_node_label        = "node-role.kubernetes.io/master"
  kubelet_node_taints       = "node-role.kubernetes.io/master=:NoSchedule"
  use_metadata              = false
}

resource "matchbox_group" "controller" {
  count   = "${length(var.tectonic_metal_controller_names)}"
  name    = "${format("%s-%s", var.tectonic_cluster_name, element(var.tectonic_metal_controller_names, count.index))}"
  profile = "${matchbox_profile.tectonic_controller.name}"

  selector {
    mac = "${element(var.tectonic_metal_controller_macs, count.index)}"
    os  = "installed"
  }

  metadata {
    domain_name        = "${element(var.tectonic_metal_controller_domains, count.index)}"
    etcd_enabled       = "${length(compact(var.tectonic_etcd_servers)) != 0 ? "false" : "true"}"
    ssh_authorized_key = "${var.tectonic_ssh_authorized_key}"

    ign_bootkube_path_unit_json            = "${jsonencode(module.bootkube.systemd_path_unit_rendered)}"
    ign_bootkube_service_json              = "${jsonencode(module.bootkube.systemd_service_rendered)}"
    ign_custom_ca_certs_json               = "${jsonencode(join("\n", module.ignition_masters.ca_cert_pem_list))}"
    ign_docker_dropin_json                 = "${jsonencode(module.ignition_masters.docker_dropin_rendered)}"
    ign_etcd_dropin_json                   = "${jsonencode(module.ignition_masters.etcd_dropin_rendered_list[count.index])}"
    ign_installer_kubelet_env_json         = "${jsonencode(module.ignition_masters.installer_kubelet_env_rendered)}"
    ign_installer_runtime_mappings_json    = "${jsonencode(module.ignition_masters.installer_runtime_mappings_rendered)}"
    ign_k8s_node_bootstrap_service_json    = "${jsonencode(module.ignition_masters.k8s_node_bootstrap_service_rendered)}"
    ign_kubelet_service_json               = "${jsonencode(module.ignition_masters.kubelet_service_rendered)}"
    ign_max_user_watches_json              = "${jsonencode(module.ignition_masters.max_user_watches_rendered)}"
    ign_tectonic_path_unit_json            = "${jsonencode(module.tectonic.systemd_path_unit_rendered)}"
    ign_tectonic_service_json              = "${jsonencode(module.tectonic.systemd_service_rendered)}"
    ign_update_ca_certificates_dropin_json = "${jsonencode(module.ignition_masters.update_ca_certificates_dropin_rendered)}"
  }
}

module "ignition_workers" {
  source = "../../modules/ignition"

  bootstrap_upgrade_cl    = "${var.tectonic_bootstrap_upgrade_cl}"
  container_images        = "${var.tectonic_container_images}"
  custom_ca_cert_pem_list = "${var.tectonic_custom_ca_pem_list}"
  etcd_ca_cert_pem        = "${module.etcd_certs.etcd_ca_crt_pem}"
  image_re                = "${var.tectonic_image_re}"
  ingress_ca_cert_pem     = "${module.ingress_certs.ca_cert_pem}"
  kube_ca_cert_pem        = "${module.kube_certs.ca_cert_pem}"
  kube_dns_service_ip     = "${module.bootkube.kube_dns_service_ip}"
  kubelet_cni_bin_dir     = "${var.tectonic_networking == "calico" || var.tectonic_networking == "canal" ? "/var/lib/cni/bin" : "" }"
  kubelet_debug_config    = "${var.tectonic_kubelet_debug_config}"
  kubelet_node_label      = "node-role.kubernetes.io/node"
  kubelet_node_taints     = ""
}

resource "matchbox_group" "worker" {
  count   = "${length(var.tectonic_metal_worker_names)}"
  name    = "${format("%s-%s", var.tectonic_cluster_name, element(var.tectonic_metal_worker_names, count.index))}"
  profile = "${matchbox_profile.tectonic_worker.name}"

  selector {
    mac = "${element(var.tectonic_metal_worker_macs, count.index)}"
    os  = "installed"
  }

  metadata {
    domain_name        = "${element(var.tectonic_metal_worker_domains, count.index)}"
    ssh_authorized_key = "${var.tectonic_ssh_authorized_key}"

    # extra data
    kubelet_image_url  = "${replace(var.tectonic_container_images["hyperkube"],var.tectonic_image_re,"$1")}"
    kubelet_image_tag  = "${replace(var.tectonic_container_images["hyperkube"],var.tectonic_image_re,"$2")}"
    kube_version_image = "${var.tectonic_container_images["kube_version"]}"

    ign_custom_ca_certs_json               = "${jsonencode(join("\n", module.ignition_workers.ca_cert_pem_list))}"
    ign_docker_dropin_json                 = "${jsonencode(module.ignition_workers.docker_dropin_rendered)}"
    ign_installer_kubelet_env_json         = "${jsonencode(module.ignition_workers.installer_kubelet_env_rendered)}"
    ign_installer_runtime_mappings_json    = "${jsonencode(module.ignition_workers.installer_runtime_mappings_rendered)}"
    ign_k8s_node_bootstrap_service_json    = "${jsonencode(module.ignition_workers.k8s_node_bootstrap_service_rendered)}"
    ign_kubelet_service_json               = "${jsonencode(module.ignition_workers.kubelet_service_rendered)}"
    ign_max_user_watches_json              = "${jsonencode(module.ignition_workers.max_user_watches_rendered)}"
    ign_update_ca_certificates_dropin_json = "${jsonencode(module.ignition_workers.update_ca_certificates_dropin_rendered)}"
  }
}
