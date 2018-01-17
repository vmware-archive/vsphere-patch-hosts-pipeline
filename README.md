# vsphere-patch-hosts-pipeline
The purpose of this pipeline is to automate the patching of vSphere ESXi Hosts.  It utilizes govc to execute commands remotely against all hosts in a given vCenter instance or optionally in a single cluster.  The hosts will be patched one at a time until all hosts have been patched.

## Prerequisites
* You need to have Concourse CI running with a worker that has access to the vCenter instance containing the hosts to be patched.
* You need to have vMotion working so that as hosts are patched they can move their VMs to a different host.

## Parameters
`params.yml` provides parameters for controlling how the pipeline runs. Fill this out before flying the pipeline.

* `vcenter_url` - IP Address or Host name for the vCenter you want to target
* `vcenter_username` - Username for vCenter defined by `vcenter_url`
* `vcenter_password` - Password for `vcenter_username`
* `vcenter_insecure` - True or False value indicating whether or not to ignore the SSL Certificate errors
* `build_number` - Optional (Latest will be used if not provided) https://esxi-patches.v-front.de used as reference.
* `cluster_name` - Optional (All will be patched if not passed) Cluster to patch hosts in.

## Fly the pipeline

### Login to your Concourse instance
`fly -t <name> login -c <concourse url>`

### Upload the pipeline to Concourse
`fly -t <name> set-pipeline -p <pipeline name> -c pipeline.yml --load-vars-from params.yml`
