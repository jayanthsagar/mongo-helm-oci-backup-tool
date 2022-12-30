FROM ubuntu:18.04
RUN apt-get update && apt-get install -y bash curl wget gnupg apt-transport-https apt-utils lsb-release \
 && rm -rf /var/lib/apt/lists/*
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8
RUN curl -fsSL https://debian.neo4j.com/neotechnology.gpg.key |gpg --dearmor -o /usr/share/keyrings/neo4j.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/neo4j.gpg] https://debian.neo4j.com stable 4.2" | tee -a /etc/apt/sources.list.d/neo4j.list

RUN echo "neo4j-enterprise neo4j/question select I ACCEPT" | debconf-set-selections
RUN echo "neo4j-enterprise neo4j/license note" | debconf-set-selections

RUN curl -sL "https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh" | bash -s -- --accept-all-defaults
RUN apt-get update && apt-get install -y neo4j-enterprise=1:4.2.7 unzip less && rm -rf /var/lib/apt/lists/*
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip awscliv2.zip && ./aws/install && rm awscliv2.zip
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

RUN mkdir /data
ADD backup.sh /scripts/backup.sh
RUN chmod +x /scripts/backup.sh

CMD ["/scripts/backup.sh"]
