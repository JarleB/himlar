# Assuming trusted_node_data = true in puppet.conf
# https://docs.puppetlabs.com/puppet/3/reference/lang_variables.html#trusted-node-data
#
# We expect a certain certname format, e.g
#  * location-role-identifier.domain.com
#  * bgo-haproxy-01.snakeoil.internal
#
# Parse data from $trusted['certname'] for hiera lookup
$verified_certname = $::trusted['certname']
$certname_a        = split($::verified_certname, '-')
$location          = $::certname_a[0]
$role              = $::certname_a[1]

# Query for classes_$runmode if $runmode is set
if $::runmode {
  hiera_include("classes_$runmode", [])
} else {
  hiera_include('classes', [])
}

# Empty default node
node default { }

