#!/usr/local/bin/bash

NAMESPACE="waiops"                                      # Namespace where NOI installed
NOI_INSTANCE_NAME="evtmanager"                              # NOI instance name

CONFIG_MAP="${NOI_INSTANCE_NAME}-ldap-proxy-config"     # Openldap config map (Important!!! Key inside the configmap should match filename, it should be like "ldap-proxy-slapd-replace")
CONFIG_DIR_PREFIX="openldap"                            # Folder for customized file "ldap-proxy-slapd-replace"



# Updating the configmap with adjusted key
CM_FILE=$(mktemp -d)/config-map.json
oc get cm ${CONFIG_MAP} -n ${NAMESPACE} -o json > ${CM_FILE}

DATA_FILES_DIR=$(mktemp -d)
files=$(cat ${CM_FILE} | jq '.data' | jq -r 'keys[]')
for k in ${files}; do
    name=".data[\"${k}\"]"
    FILE="${CONFIG_DIR_PREFIX}/${k}"
    if [[ -f "${FILE}" ]]; then
        cat ${FILE} > ${DATA_FILES_DIR}/${k};
    else
        cat ${CM_FILE} | jq -r ${name} > ${DATA_FILES_DIR}/${k};
    fi
done

oc create cm ${CONFIG_MAP} --from-file ${DATA_FILES_DIR} -o yaml --dry-run=client | oc apply -f -

rm -rf ${CM_FILE}
rm -rf ${DATA_FILES_DIR}


# Checking version of WatsonAIOp to select image.
if [ $(oc get statefulset ${NOI_INSTANCE_NAME}-openldap -o jsonpath='{range .spec.template.spec.containers[*].securityContext.capabilities}{.add}{"\n"}{end}') ]; then
    # Watson AIOps 3.1 (linux capabilities granted)
    echo "Linux capabilities granted...";
    strOpenLdapCustomImage="quay.io/oleg_samoylov_ru/noi_openldap_cap@sha256:fc3a73436f35ea041fe9da95f844ffdb5af669575c77a0525af7bab3b6ee0924"
else
    # Watson AIOps 3.2 (linux capabilities forbidden)
    echo "Linux capabilities forbidden, Ok...";
    strOpenLdapCustomImage="quay.io/oleg_samoylov_ru/noi_openldap_nocap@sha256:62dce0ca1e3863682b85e1adf9f57789bb0cee66b9aa4483455bccb4dd1c8a72"
fi


# Adjusting openldap statefulset with custom image name
jsonPatch=$(cat <<EOF
{
    "spec": {
        "template": {
            "spec": {
                "containers": [
                    {
                        "name": "openldap",
                        "image": "${strOpenLdapCustomImage}"
                    }
                ]
            }
        }
    }
}
EOF
)

# Patching statefulset with additional volumes from configmap
oc scale statefulset ${NOI_INSTANCE_NAME}-openldap --replicas=0 -n ${NAMESPACE}
oc patch statefulset ${NOI_INSTANCE_NAME}-openldap -p "${jsonPatch}" -n ${NAMESPACE}
oc scale statefulset ${NOI_INSTANCE_NAME}-openldap --replicas=1 -n ${NAMESPACE}

oc scale statefulset ${NOI_INSTANCE_NAME}-webgui --replicas=0 -n ${NAMESPACE}
oc scale statefulset ${NOI_INSTANCE_NAME}-webgui --replicas=1 -n ${NAMESPACE}

oc scale statefulset ${NOI_INSTANCE_NAME}-nciserver --replicas=0 -n ${NAMESPACE}
oc scale statefulset ${NOI_INSTANCE_NAME}-nciserver --replicas=1 -n ${NAMESPACE}

oc scale statefulset ${NOI_INSTANCE_NAME}-impactgui --replicas=0 -n ${NAMESPACE}
oc scale statefulset ${NOI_INSTANCE_NAME}-impactgui --replicas=1 -n ${NAMESPACE}




