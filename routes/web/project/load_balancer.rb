# frozen_string_literal: true

class CloverWeb
  hash_branch(:project_prefix, "load-balancer") do |r|
    r.get true do
      @lbs = Serializers::LoadBalancer.serialize(@project.load_balancers_dataset.authorized(@current_user.id, "LoadBalancer:view").all, {include_path: true})

      view "networking/load_balancer/index"
    end

    r.post true do
      Authorization.authorize(@current_user.id, "LoadBalancer:create", @project.id)

      ps = PrivateSubnet.from_ubid(r.params["private_subnet_id"])
      Authorization.authorize(@current_user.id, "PrivateSubnet:view", ps.id)

      lb = Prog::Vnet::LoadBalancerNexus.assemble(
        ps.id,
        name: r.params["name"],
        algorithm: r.params["algorithm"],
        src_port: r.params["src_port"],
        dst_port: r.params["dst_port"],
        health_check_endpoint: r.params["health_check_endpoint"],
        health_check_interval: r.params["health_check_interval"],
        health_check_timeout: r.params["health_check_timeout"],
        health_check_up_threshold: r.params["health_check_up_threshold"],
        health_check_down_threshold: r.params["health_check_down_threshold"]
      ).subject

      flash["notice"] = "'#{r.params["name"]}' is created"

      r.redirect "#{@project.path}#{lb.path}"
    end

    r.on "create" do
      r.get true do
        Authorization.authorize(@current_user.id, "LoadBalancer:create", @project.id)
        authorized_subnets = @project.private_subnets_dataset.authorized(@current_user.id, "PrivateSubnet:view").all
        @subnets = Serializers::PrivateSubnet.serialize(authorized_subnets)
        view "networking/load_balancer/create"
      end
    end
  end
end
