FROM ubuntu:22.04



ENV DEBIAN_FRONTEND=noninteractive



RUN apt-get update && apt-get install -y \

    openarena-server \

    findutils \

    && rm -rf /var/lib/apt/lists/*



RUN mkdir -p /root/.openarena/baseoa



EXPOSE 27960/udp



CMD ["/bin/bash", "-c", "BINARIO=$(find /usr -name '*ded*' -o -name '*server*' | grep -E 'openarena|ioq3' | head -n 1); if [-z '$BINARIO' ]; then BINARIO='openarena-server'; fi; exec $BINARIO +set dedicated 1 +exec server.cfg"]

