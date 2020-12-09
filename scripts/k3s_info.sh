#! /bin/bash

eval "$(jq -r '@sh "ADDRESS=\(.host) PRIVATE_KEY=\(.private_key) FILE=\(.file)"')"

if [ -z "$ADDRESS" ]
then
  exit 1
fi

ID_FILE=$(mktemp)
chmod 600 $ID_FILE
echo "${PRIVATE_KEY}" >"$ID_FILE"
clean_up() {
  ARG=$?
  rm $ID_FILE
  exit $ARG
}
trap clean_up EXIT

CONTENT=$(
  ssh -i "$ID_FILE" \
    -o ConnectTimeout=5 \
    -o 'StrictHostKeyChecking no' \
    -o 'UserKnownHostsFile /dev/null' \
    "ubuntu@${ADDRESS}" \
    "sudo cat ${FILE}"
)

KUBE_CA=$(echo "$CONTENT" | yq r -j - | jq -r ".clusters[0].cluster[\"certificate-authority-data\"]")
KUBE_USER=$(echo "$CONTENT" | yq r -j - | jq -r ".users[0].user.username")
KUBE_PASS=$(echo "$CONTENT" | yq r -j - | jq -r ".users[0].user.password")

jq -n --arg content "$CONTENT" \
 --arg ca "$KUBE_CA" \
 --arg user "$KUBE_USER" \
 --arg pass "$KUBE_PASS" \
 '{"content":$content, "ca": $ca, "user": $user, "pass": $pass}'
