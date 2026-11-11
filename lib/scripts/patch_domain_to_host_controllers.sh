#!/bin/bash
# patch_domain_to_host_controllers.sh
# Run from your Rails root directory on macOS.

set -euo pipefail

echo "Patching controller parameters from :domain to :host for DymondSite mappings..."

# Update server_instances_controller.rb permit parameters and attributes
sed -i '' 's/attributes = params.require(:application).permit(:name, :domain,/attributes = params.require(:application).permit(:name, :host,/g' app/controllers/dashboard/server_instances_controller.rb
sed -i '' 's/owner: owner, name: attributes\[:name\], domain: attributes\[:domain\]/owner: owner, name: attributes[:name], host: attributes[:host]/g' app/controllers/dashboard/server_instances_controller.rb

# Update application_launches_controller.rb permit parameters
sed -i '' 's/permit(:template_id, :owner_id, :name, :domain,/permit(:template_id, :owner_id, :name, :host,/g' app/controllers/dashboard/application_launches_controller.rb

echo "Controllers patched successfully!"
git diff app/controllers/dashboard/