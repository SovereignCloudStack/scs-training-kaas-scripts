#!/bin/bash

set -e

# Create the openstack config directory if it doesn't exist
mkdir -p ~/.config/openstack

# Check for cert files in the current directory
CERT_FILE=$(find . -maxdepth 1 -name "*.cert" ! -name "*.sample" | head -n 1)

if [ -n "$CERT_FILE" ]; then
    echo "Found certificate file: $CERT_FILE"
    # Copy cert file to openstack config directory
    cp "$CERT_FILE" ~/.config/openstack/
    CERT_FILENAME=$(basename "$CERT_FILE")
    CERT_ABSOLUTE_PATH="$HOME/.config/openstack/$CERT_FILENAME"
    echo "Copied $CERT_FILE to $CERT_ABSOLUTE_PATH"
fi

# Check for clouds.yaml file
if [ -f "clouds.yaml" ]; then
    echo "Found clouds.yaml file"
    
    # If both cert and clouds.yaml exist, update the cacert path
    if [ -n "$CERT_FILE" ]; then
        echo "Updating cacert path in clouds.yaml to: $CERT_ABSOLUTE_PATH"
        
        # Check if cacert line exists in the file
        if grep -q "cacert:" clouds.yaml; then
            # Update existing cacert line
            sed "s|cacert:.*|cacert: \"$CERT_ABSOLUTE_PATH\"|g" clouds.yaml > clouds.yaml.tmp
        else
            # Add cacert line under the cloud config (assuming the cloud name is at the correct indentation)
            awk -v cert="$CERT_ABSOLUTE_PATH" '
                /^  [a-zA-Z0-9_-]+:/ { cloud_found = 1 }
                cloud_found && /^    auth:/ { 
                    print
                    print "    cacert: \"" cert "\""
                    cloud_found = 0
                    next
                }
                { print }
            ' clouds.yaml > clouds.yaml.tmp
        fi
        mv clouds.yaml.tmp clouds.yaml
    else
        echo "No certificate file found, removing cacert entry if present"
        # Remove cacert line if no cert file exists
        sed '/cacert:/d' clouds.yaml > clouds.yaml.tmp
        mv clouds.yaml.tmp clouds.yaml
    fi
    
    # Copy clouds.yaml to openstack config directory
    cp clouds.yaml ~/.config/openstack/
    echo "Copied clouds.yaml to ~/.config/openstack/"
fi

echo "OpenStack configuration preparation complete"