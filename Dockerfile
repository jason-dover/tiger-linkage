# Based on the official dev tigergraph dockerfile: https://github.com/tigergraph/ecosys/blob/master/demos/guru_scripts/docker/dockerfile
# Modifications based on https://github.com/DavidBakerEffendi/tigergraph/blob/master/3/3.0.5/

# Official version used ubuntu:16.04 (~126MB); switched to slim debian to cut size down to ~52MB
FROM debian:jessie-slim

ENV DEV_VERSION 3.0.5
RUN useradd -ms /bin/bash tigergraph

RUN apt-get -qq update && apt-get install -y --no-install-recommends sudo curl iproute2 net-tools cron ntp locales vim tar jq uuid-runtime openssh-client openssh-server > /dev/null && \
  mkdir /var/run/sshd && \
  echo 'root:root' | chpasswd && \
  echo 'tigergraph:tigergraph' | chpasswd && \
  sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
  sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd && \
  echo "tigergraph    ALL=(ALL)       NOPASSWD: ALL" >> /etc/sudoers &&   apt-get clean -y && \
  curl -s -k -L https://dl.tigergraph.com/developer-edition/tigergraph-3.0.5-developer.tar.gz \
    -o /home/tigergraph/tigergraph-dev.tar.gz && \
  /usr/sbin/sshd && cd /home/tigergraph/ && \
  tar xfz tigergraph-dev.tar.gz && \
  rm -f tigergraph-dev.tar.gz && \
  cd /home/tigergraph/tigergraph-* && \
  ./install.sh -n || : && \
  mkdir -p /home/tigergraph/tigergraph/logs && \
  rm -fR /home/tigergraph/tigergraph-* && \
  rm -fR /home/tigergraph/tigergraph/app/3.0.5/syspre_pkg && \
  rm -f /home/tigergraph/tigergraph/gium_prod.tar.gz && \
  rm -f /home/tigergraph/tigergraph/pkg_pool/tigergraph_*.tar.gz && \
  cd /tmp && rm -rf /tmp/tigergraph-* && \
  curl -s -k -L "https://github.com/tigergraph/gsql-graph-algorithms/tarball/master" -o /tmp/algorithms.tgz && \
  tar xzf algorithms.tgz && mv /tmp/tigergraph-gsql-graph-algorithms-* /home/tigergraph/gsql-graph-algorithms && \
  rm -rf /tmp/*  && \
  echo "export VISIBLE=now" >> /etc/profile && \
  echo "export USER=tigergraph" >> /home/tigergraph/.bash_tigergraph && \
  rm -f /home/tigergraph/.gsql_fcgi/RESTPP.socket.1 && \
  mkdir -p /home/tigergraph/.gsql_fcgi && \
  touch /home/tigergraph/.gsql_fcgi/RESTPP.socket.1 && \
  chmod 644 /home/tigergraph/.gsql_fcgi/RESTPP.socket.1 && \
  chown -R tigergraph:tigergraph /home/tigergraph

EXPOSE 22
# Here, changing the offical version to instead start all gadmin commands automatically; then, updating the admin logs to write to the container logs directly
ENTRYPOINT /usr/sbin/sshd && su - tigergraph bash -c "/home/tigergraph/tigergraph/app/cmd/gadmin start all" && \
  su - tigergraph bash -c "tail -f /home/tigergraph/tigergraph/log/admin/ADMIN.INFO" 
