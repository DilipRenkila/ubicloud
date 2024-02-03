# frozen_string_literal: true

class Prog::Storage::SetupSpdk < Prog::Base
  subject_is :sshable, :vm_host

  required_input :version
  optional_input :should_start_service, false
  optional_input :allocation_weight, 0

  SUPPORTED_SPDK_VERSIONS = [
    ["v23.09", "arm64"],
    ["v23.09", "x64"],
    ["v23.09-ubi-0.2", "x64"]
  ]

  def self.assemble(vm_host_id, version, start_service: false, allocation_weight: 0)
    Strand.create_with_id(
      prog: "Storage::SetupSpdk",
      label: "start",
      stack: [{
        "subject_id" => vm_host_id,
        "version" => version,
        "should_start_service" => start_service,
        "allocation_weight" => allocation_weight
      }]
    )
  end

  label def start
    arch = vm_host.arch

    fail "Unsupported version: #{version}, #{arch}" unless SUPPORTED_SPDK_VERSIONS.include? [version, arch]

    fail "Can't install more than 2 SPDKs on a host" if vm_host.spdk_installations.length > 1

    fail "No available hugepages" if should_start_service && vm_host.used_hugepages_1g == vm_host.total_hugepages_1g

    SpdkInstallation.create(
      version: version,
      allocation_weight: 0,
      vm_host_id: vm_host.id
    ) { _1.id = SpdkInstallation.generate_uuid }

    hop_install_spdk
  end

  label def install_spdk
    sshable.cmd("sudo host/bin/setup-spdk install #{version.shellescape}")

    hop_start_service
  end

  label def start_service
    if should_start_service
      q_version = version.shellescape
      sshable.cmd("sudo host/bin/setup-spdk start #{q_version}")
      sshable.cmd("sudo host/bin/setup-spdk verify #{q_version}")
    end

    hop_update_database
  end

  label def update_database
    SpdkInstallation.where(
      version: version,
      vm_host_id: vm_host.id
    ).update(allocation_weight: allocation_weight)

    if should_start_service
      VmHost.where(id: vm_host.id).update(used_hugepages_1g: Sequel[:used_hugepages_1g] + 1)
    end

    pop "SPDK was setup"
  end
end
