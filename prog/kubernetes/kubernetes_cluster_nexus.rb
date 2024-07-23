class Prog::Kubernetes::KubernetesClusterNexus < Prog::Base
  subject_is :kubernetes_cluster

  label def start
    kubernetes_cluster.create_cluster_vms
    hop_wait_for_vms
  end

  label def wait_for_vms
    if kubernetes_cluster.nodes.all? { _1.vm.strand.label == "wait" }
      hop_configure_kubernetes
    else
      nap 30
    end
  end

  # ... other labels for configuring Kubernetes, etc.
end

