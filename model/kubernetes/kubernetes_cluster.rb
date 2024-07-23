# frozen_string_literal: true

require_relative "../../model"

class KubernetesCluster < Sequel::Model
  one_to_one :strand, key: :id
  many_to_one :project
  one_to_many :active_billing_records, class: :BillingRecord, key: :resource_id do |ds| ds.active end
  one_to_many :nodes, class: KubernetesNode, key: :cluster_id
  one_to_one :master_node, class: KubernetesNode, key: :cluster_id, conditions: {is_master: true}
  many_to_one :private_subnet

  plugin :association_dependencies, firewall_rules: :destroy
  dataset_module Authorization::Dataset
  dataset_module Pagination

  include ResourceMethods
  include SemaphoreMethods
  include Authorization::HyperTagMethods
  include Authorization::TaggableMethods

  semaphore :initial_provisioning, :update_firewall_rules, :refresh_dns_record, :destroy

  plugin :column_encryption do |enc|
    enc.column :kubeconfig
  end

  def display_location
    LocationNameConverter.to_display_name(location)
  end

  def path
    "/location/#{display_location}/kubernetes/#{name}"
  end

  def hyper_tag_name(project)
    "project/#{project.ubid}/location/#{display_location}/kubernetes/#{name}"
  end

  def display_state
    return "running" if ["wait", "update_nodes"].include?(strand.label) && !initial_provisioning_set?
    return "deleting" if destroy_set? || strand.label == "destroy"
    "creating"
  end

  def hostname
    "#{name}.#{ubid}.#{Config.kubernetes_service_hostname}"
  end

  def identity
    "#{ubid}.#{Config.kubernetes_service_hostname}"
  end


  def self.redacted_columns
    super + [:kubeconfig]
  end

  def create_node_vm(node_type: 'worker')
    vm = Vm.create_with_id(
      project_id: self.project_id,
      location: self.location,
      name: "#{self.name}-#{node_type}-#{SecureRandom.hex(4)}",
      family: "standard",
      cores: node_type == 'master' ? 2 : 1,
      arch: "x64",
      boot_image: "ubuntu-jammy",
      ip4_enabled: false
    )

    # Associate the VM with this cluster
    KubernetesNode.create_with_id(
      cluster_id: self.id,
      vm_id: vm.id,
      is_master: node_type == 'master'
    )

    # Start the VM provisioning process
    Strand.create(prog: "Vm::VmNexus", label: "start") { _1.id = vm.id }

    vm
  end

  def create_cluster_vms
    create_node_vm(node_type: 'master')
    2.times { create_node_vm(node_type: 'worker') }
  end

end
