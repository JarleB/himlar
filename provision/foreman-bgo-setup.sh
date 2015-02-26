#!/bin/bash


# Register Foreman host in DNS and CNAMEs admin and puppet
echo "update add bgo-foreman-bootstrap.mgmt.iaas.intern. 300 A 172.16.32.11
      update add admin.mgmt.iaas.intern. 3600 CNAME bgo-foreman-bootstrap.mgmt.iaas.intern.
      update add puppet.mgmt.iaas.intern. 3600 CNAME bgo-foreman-bootstrap.mgmt.iaas.intern.
      send" | nsupdate -k /etc/rndc.key

#
# Foreman settings
#
rootpw='himlar-changeme'
rootpw_md5=$(openssl passwd -1 $rootpw)
echo '
  Setting["root_pass"]        = "'$rootpw_md5'"
  Setting["entries_per_page"] = 100
  Setting["foreman_url"]      = "https://admin.mgmt.iaas.intern."
  Setting["unattended_url"]   = "http://admin.mgmt.iaas.intern."
' | foreman-rake console

#
# Network configuration objects
#
hammer domain create --name "bmc.iaas.intern"
hammer domain info --name "bmc.iaas.intern"
hammer domain create --name "mgmt.iaas.intern"
hammer domain info --name "mgmt.iaas.intern"

hammer subnet create --name "mgmt" \
  --network "172.16.32.0" \
  --mask "255.255.248.0" \
  --gateway "172.16.32.1" \
  --dns-primary "129.177.6.54" \
  --dns-secondary "129.177.12.31"
hammer subnet update --name "mgmt" \
  --domain-ids $(hammer domain list | grep "mgmt.iaas.intern" | head -c1)
hammer subnet update --name "mgmt" \
  --dhcp-id $(hammer proxy list | grep foreman | head -c2)
hammer subnet update --name "mgmt" \
  --tftp-id $(hammer proxy list | grep foreman | head -c2)
hammer subnet update --name "mgmt" \
  --dns-id $(hammer proxy list | grep foreman | head -c2)
hammer subnet info --name "mgmt"
hammer subnet update --name "mgmt" --from 172.16.32.200 --to 172.16.32.250
hammer domain update --name mgmt.iaas.intern --dns-id $(hammer proxy list | grep foreman | head -c2)

hammer subnet create --name "bmc" \
  --network "172.16.24.0" \
  --mask "255.255.248.0" \
  --gateway "172.16.24.1" \
  --dns-primary "129.177.6.54" \
  --dns-secondary "129.177.12.31"
hammer subnet update --name "bmc" \
  --domain-ids $(hammer domain list | grep "bmc.iaas.intern" | head -c1)
hammer domain update --name bmc.iaas.intern --dns-id $(hammer proxy list | grep foreman | head -c2)

#
# Puppet settings
#
# Enable Puppetlabs repo to enable Puppet bootstrap logic in kickstart template
hammer global-parameter set --name enable-puppetlabs-repo --value true
# Set up Puppet environment and import classes from proxy id 1
hammer environment create --name "production"
hammer environment info --name "production"
hammer proxy import-classes --environment "production" --id $(hammer proxy list | grep foreman | head -c2)

#
# Provisioning and discovery setup
#
# Create OS
hammer os create --name CentOS --major 7 --minor 0.1406 --description "CentOS 7.0" --family Redhat \
  --architecture-ids 1 \
  --medium-ids $(hammer medium list | grep CentOS | head -c1) \
  --ptable-ids $(hammer partition-table list | grep "Kickstart default" | head -c1) 

# Download and create templates
wget -P /tmp http://folk.uib.no/edpto/provision_openstack.erb
wget -P	/tmp http://folk.uib.no/edpto/provision_kickstart_ifs.erb
hammer template create --name "Kickstart_openstack" --type provision --file /tmp/provision_openstack.erb
hammer template create --name "Kickstart default PXELinux ifs" --type PXELinux --file /tmp/provision_kickstart_ifs.erb
# Assign templates to OS
hammer template update --name "Kickstart default PXELinux ifs" --operatingsystem-ids 1
hammer template update --name "Kickstart_openstack" --operatingsystem-ids 1
hammer os set-default-template --id 1 \
  --config-template-id $(hammer template list --per-page 10000 | grep "Kickstart_openstack"|cut -d" " -f1) 
hammer os set-default-template --id 1 \
  --config-template-id $(hammer template list --per-page 10000 | grep "Kickstart default PXELinux ifs" | cut -d" " -f1)
hammer os update --id 1 \
  --ptable-ids $(hammer partition-table list --per-page 10000 | grep "Kickstart default" | cut -d" " -f1)

# Create a base hostgroup with all services on proxy id 1
hammer hostgroup create --name "base" --architecture "x86_64" --domain-id 1 --environment "production" --operatingsystem-id 1 --medium "CentOS mirror" --ptable "Kickstart default" --subnet "mgmt" --puppet-proxy-id 1 --puppet-ca-proxy-id 1

# Get our custom provision templates
foreman-rake templates:sync repo="https://github.com/norcams/community-templates.git" branch="norcams"
# Render pxe default with safe mode rendering false - this is required for the discovery image
# to get the foreman_url setting passed through to the kernel from the template
echo '
  Setting["safemode_render"] = false
  include Foreman::Renderer
  ConfigTemplate.build_pxe_default(self)
  Setting["safemode_render"] = true
' | foreman-rake console
