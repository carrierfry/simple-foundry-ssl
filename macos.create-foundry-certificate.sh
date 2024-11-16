#!/bin/sh
set -eu

RED='\033[0;31m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
DEFAULT_COLOUR='\033[0m'

# Verify, that openssl is available

if [ -z "$(which openssl)" ]; then
    echo "${RED}[ERROR] Cannot proceed because openssl is not installed.${DEFAULT_COLOUR}"
    echo "${RED}        Please install the openssl package.${DEFAULT_COLOUR}"
    echo "${RED}        If you use homebrew, you can run${DEFAULT_COLOUR} brew install openssl@3"
    echo "${RED}        If you use MacPorts, you can run${DEFAULT_COLOUR} port install openssl"
    exit 1
fi

# Get the path in which to create the certificate

CERTIFICATE_PATH=${CERTIFICATE_PATH:-./certificate}
echo "${ORANGE}In which directory do you want to create the certificate? Enter a path or just press Enter to create it under ${CERTIFICATE_PATH}.${DEFAULT_COLOUR}"
read CUSTOM_CERTIFICATE_PATH
if [ -n "$CUSTOM_CERTIFICATE_PATH" ]; then
    CERTIFICATE_PATH="$CUSTOM_CERTIFICATE_PATH"
fi

CERTIFICATE_BASE_NAME=localhost
PEM_FILE_NAME="$CERTIFICATE_BASE_NAME.pem"
KEY_FILE_NAME="$CERTIFICATE_BASE_NAME.key"

mkdir -p "$CERTIFICATE_PATH"

# Create the certificate

openssl req -newkey rsa:2048 \
            -x509 \
            -sha256 \
            -days 36500 \
            -nodes \
            -out "$CERTIFICATE_PATH/$PEM_FILE_NAME" \
            -keyout "$CERTIFICATE_PATH/$KEY_FILE_NAME" \
            -subj "/CN=localhost" \
            -extensions v3_req

echo "${GREEN}[SUCCESS] The generated certificate files can be found in $CERTIFICATE_PATH and are called $PEM_FILE_NAME and $KEY_FILE_NAME.${DEFAULT_COLOUR}"

# Show the content of the certificate

if [ "${DEBUG:-false}" = "true" ]; then
    echo "${GREEN}[SUCCESS] Here is an overview over the content of $CERTIFICATE_PATH/$PEM_FILE_NAME:${DEFAULT_COLOUR}"
    openssl x509 -in "$CERTIFICATE_PATH/$PEM_FILE_NAME" -text -noout
fi

# Register the certificate in Foundry

echo "${ORANGE}Do you want to automatically configure the newly created certificate for Foundry? [y/N]${DEFAULT_COLOUR}"
read CONFIGURE_FOUNDRY
if [ "$CONFIGURE_FOUNDRY" = "y" ] || [ "$CONFIGURE_FOUNDRY" = "Y" ]; then
    echo "${ORANGE}Which directory is Foundry installed at? In this path, there will be directories named "Config", "Data", and "Logs". (Current path: $(pwd))${DEFAULT_COLOUR}"
    FOUNDRY_PATH=""
    until [ -d "$FOUNDRY_PATH" ] && [ -d "$FOUNDRY_PATH/Config" ]; do
        read FOUNDRY_PATH
        if [ ! -d "$FOUNDRY_PATH" ] || [ ! -d "$FOUNDRY_PATH/Config" ]; then
            echo "${RED}[ERROR] \"$FOUNDRY_PATH\" is not a valid Foundry installation path. Please try again.${DEFAULT_COLOUR}"
        fi
    done

    # Validate, that the options.json file exists
    if [ ! -f "$FOUNDRY_PATH/Config/options.json" ]; then
        echo "${RED}[ERROR] The Foundry configuration file \"$FOUNDRY_PATH/Config/options.json\" was not found. Quitting.${DEFAULT_COLOUR}"
        exit 1
    fi

    # Copy the SSL certificate files into the Foundry config directory
    cp "$CERTIFICATE_PATH/$PEM_FILE_NAME" "$FOUNDRY_PATH/Config"
    cp "$CERTIFICATE_PATH/$KEY_FILE_NAME" "$FOUNDRY_PATH/Config"
    chmod a+r "$FOUNDRY_PATH/Config/$PEM_FILE_NAME"
    chmod a+r "$FOUNDRY_PATH/Config/$KEY_FILE_NAME"

    # Set the certificate files in the configuration file
    sed -i '.bak' 's/"sslCert": null/"sslCert": ""/1' "$FOUNDRY_PATH/Config/options.json"
    sed -i '.bak' 's/"sslCert": ".*"/"sslCert": "'${PEM_FILE_NAME}'"/1' "$FOUNDRY_PATH/Config/options.json"
    sed -i '.bak' 's/"sslKey": null/"sslKey": ""/1' "$FOUNDRY_PATH/Config/options.json"
    sed -i '.bak' 's/"sslKey": ".*"/"sslKey": "'${KEY_FILE_NAME}'"/1' "$FOUNDRY_PATH/Config/options.json"
    rm "$FOUNDRY_PATH/Config/options.json.bak"

    echo "${GREEN}[SUCCESS] The certificate has been installed. You may have to restart Foundry for the changes to take effect.${DEFAULT_COLOUR}"

    echo "${GREEN}[SUCCESS] You can delete the directory $CERTIFICATE_PATH if you don't need the certificates for anything else. The required files have been copied to Foundry's configuration directory.${DEFAULT_COLOUR}"
else
    echo "${ORANGE}[INFO] Not configuring the certificate for Foundry.${DEFAULT_COLOUR}"
    echo "${ORANGE}[INFO] If you want to do this manually, move the files ${DEFAULT_COLOUR}$CERTIFICATE_PATH/$PEM_FILE_NAME${ORANGE} and ${DEFAULT_COLOUR}$CERTIFICATE_PATH/$KEY_FILE_NAME${ORANGE} into your Foundry's ${DEFAULT_COLOUR}Config${ORANGE} directory.${DEFAULT_COLOUR}"
    echo "${ORANGE}[INFO] Then in Foundry, go to the ${DEFAULT_COLOUR}\"Application Configuration\"${ORANGE} menu and under ${DEFAULT_COLOUR}\"SSL Configuration\"${ORANGE} set ${DEFAULT_COLOUR}\"$PEM_FILE_NAME\"${ORANGE} as the Certificate and ${DEFAULT_COLOUR}\"$KEY_FILE_NAME\"${ORANGE} as the Key (without the quotation marks).${DEFAULT_COLOUR}"
fi
