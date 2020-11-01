# "Borrowed" from https://github.com/DavidBakerEffendi/tigergraph/blob/master/3/3.0.5/run.sh
#!/bin/bash

source ./config/tigergraph-config.conf

docker build -t ${DOCKER_ACC}/${DOCKER_REPO}:${TG_VERSION} --no-cache . || exit 1
read -r -p "Would you like to push the image? [y/n] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];
then
    docker push ${DOCKER_ACC}/${DOCKER_REPO}:${TG_VERSION}
fi