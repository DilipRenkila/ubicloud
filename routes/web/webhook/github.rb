# frozen_string_literal: true

class CloverWeb
  CloverBase.run_on_all_locations :delete_github_runners do |github_installation|
    github_installation.runners.each(&:incr_destroy)
  end

  hash_branch(:webhook_prefix, "github") do |r|
    r.post true do
      body = r.body.read
      unless check_signature(r.headers["x-hub-signature-256"], body)
        response.status = 401
        r.halt
      end

      response.headers["Content-Type"] = "application/json"

      data = JSON.parse(body)
      case r.headers["x-github-event"]
      when "installation"
        return handle_installation(data)
      when "workflow_job"
        return handle_workflow_job(data)
      end

      return error("Unhandled event")
    end
  end

  def error(msg)
    {error: {message: msg}}.to_json
  end

  def success(msg)
    {message: msg}.to_json
  end

  def check_signature(signature, body)
    return false unless signature
    method, actual_digest = signature.split("=")
    expected_digest = OpenSSL::HMAC.hexdigest(method, Config.github_app_webhook_secret, body)
    Rack::Utils.secure_compare(actual_digest, expected_digest)
  end

  def handle_installation(data)
    installation = GithubInstallation[installation_id: data["installation"]["id"]]
    case data["action"]
    when "deleted"
      unless installation
        return error("Unregistered installation")
      end
      delete_github_runners(installation)
      installation.destroy
      return success("GithubInstallation[#{installation.ubid}] deleted")
    end

    error("Unhandled installation action")
  end

  def handle_workflow_job(data)
    unless (installation = GithubInstallation[installation_id: data["installation"]["id"]])
      return error("Unregistered installation")
    end

    job = data.fetch("workflow_job")

    unless (label = job.fetch("labels").find { Github.runner_labels.key?(_1) })
      return error("Unmatched label")
    end

    if data["action"] == "queued"
      # Now all runners are created on the location github-runners,
      # once storage will be common we should pass/select the location
      # somehow. Then we can make the call to the right location
      st = Prog::Vm::GithubRunner.assemble(
        installation,
        repository_name: data["repository"]["full_name"],
        label: label
      )

      return success("GithubRunner[#{st.subject.ubid}] created")
    end

    # That should be providing location as well
    runner = GithubRunner.first(
      installation_id: installation.id,
      repository_name: data["repository"]["full_name"],
      runner_id: job.fetch("runner_id")
    )

    return error("Unregistered runner") unless runner

    # That should be another call to a location
    runner.update(workflow_job: job.except("steps"))

    case data["action"]
    when "in_progress"
      success("GithubRunner[#{runner.ubid}] picked job #{job.fetch("id")}")
    when "completed"
      # That should be another call to a location
      runner.incr_destroy

      success("GithubRunner[#{runner.ubid}] deleted")
    else
      error("Unhandled workflow_job action")
    end
  end
end
