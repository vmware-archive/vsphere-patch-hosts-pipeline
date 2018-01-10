# vsphere-patch-hosts-pipeline

## Parameters
`params.yml` provides parameters for controlling how the pipeline runs. Fill this out before flying the pipeline.

* `vcenter_url` - IP Address or Host name for the vCenter you want to target
* `vcenter_username` - Username for vCenter defined by `vcenter_url`
* `vcenter_password` - Password for `vcenter_username`
* `vcenter_insecure` - True or False value indicating whether or not to ignore the SSL Certificate errors

## Fly the pipeline

`fly -t <name> login -c <concourse url>` - Login to your Concourse instance

`fly -t <name> set-pipeline -p <pipeline name> -c pipeline.yml --load-vars-from params.yml` - Upload the pipeline to Concourse
