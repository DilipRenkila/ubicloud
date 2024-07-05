# frozen_string_literal: true

class CloverWeb
  hash_branch(:project_location_prefix, "load-balancer") do |r|
    r.on String do |lb_name|
      pss = @project.private_subnets_dataset.where(location: @location).all
      lb = pss.flat_map { _1.load_balancers_dataset.where { {Sequel[:load_balancer][:name] => lb_name} }.all }.first

      unless lb
        response.status = 404
        r.halt
      end

      r.get true do
        Authorization.authorize(@current_user.id, "LoadBalancer:view", lb.id)
        @lb = Serializers::LoadBalancer.serialize(lb)

        vms = lb.private_subnet.vms
        attached_vms = lb.vms
        @attachable_vms = Serializers::Vm.serialize(vms.reject { |vm| attached_vms.map(&:id).include?(vm.id) })

        view "networking/load_balancer/show"
      end

      r.delete true do
        Authorization.authorize(@current_user.id, "LoadBalancer:delete", lb.id)

        lb.incr_destroy

        return {message: "Deleting #{lb.name}"}.to_json
      end

      r.on "attach-vm" do
        r.post true do
          Authorization.authorize(@current_user.id, "LoadBalancer:edit", lb.id)
          vm = Vm.from_ubid(r.params["vm-id"])
          unless vm
            flash["error"] = "VM not found"
            response.status = 404
            r.redirect "#{@project.path}#{lb.path}"
          end

          lb.add_vm(vm)
          flash["notice"] = "VM is attached"
          r.redirect "#{@project.path}#{lb.path}"
        end
      end

      r.on "detach-vm" do
        r.post true do
          Authorization.authorize(@current_user.id, "LoadBalancer:edit", lb.id)
          vm = Vm.from_ubid(r.params["vm-id"])
          unless vm
            flash["error"] = "VM not found"
            response.status = 404
            r.redirect "#{@project.path}#{lb.path}"
          end
          lb.evacuate_vm(vm)
          lb.remove_vm(vm)
          flash["notice"] = "VM is detached"
          r.redirect "#{@project.path}#{lb.path}"
        end
      end
    end
  end
end
