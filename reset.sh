
#!/bin/bash
set -eux

terraform destroy -auto-approve

# remove any user modifications
git reset --hard origin/master
git clean -fdx
