#!/bin/bash
#Deploy Keystone
/opt/genestack/bin/install-keystone.sh

# Deploy Glance
/opt/genestack/bin/install-glance.sh

# Deploy Heat
/opt/genestack/bin/install-heat.sh

# Deploy Cinder
/opt/genestack/bin/install-cinder.sh

# Deploy placement
/opt/genestack/bin/install-placement.sh

# Deploy Nova
/opt/genestack/bin/install-nova.sh

# Deploy Neutron
/opt/genestack/bin/install-neutron.sh

# Deploy Octavia
/opt/genestack/bin/install-octavia.sh

# Deploy SkyLine
/opt/genestack/bin/install-skyline.sh
