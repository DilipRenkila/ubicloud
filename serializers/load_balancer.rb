# frozen_string_literal: true

class Serializers::LoadBalancer < Serializers::Base
  def self.serialize_internal(lb, options = {})
    base = {
      id: lb.ubid,
      name: lb.name,
      hostname: lb.hostname,
      ps: Serializers::PrivateSubnet.serialize(lb.private_subnet),
      algorithm: (lb.algorithm == "round_robin") ? "Round Robin" : "Hash Based",
      health_check_endpoint: lb.health_check_endpoint,
      health_check_interval: lb.health_check_interval,
      health_check_timeout: lb.health_check_timeout,
      health_check_unhealthy_threshold: lb.health_check_down_threshold,
      health_check_healthy_threshold: lb.health_check_up_threshold,
      src_port: lb.src_port,
      dst_port: lb.dst_port,
      vms: lb.vms.map { |vm| Serializers::Vm.serialize(vm, {load_balancer: true}) }
    }

    if options[:include_path]
      base[:path] = lb.path
    end

    base
  end
end
