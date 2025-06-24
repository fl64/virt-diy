FROM alpine:3.22

RUN apk add --no-cache \
    qemu-system-x86_64 \
    libvirt-daemon \
    virt-install \
    dnsmasq \
    ebtables \
    iproute2 \
    iptables \
    swtpm \
    curl \
    tcpdump \
    xorriso \
    jq \
    socat

# COPY start.sh /start.sh
# RUN chmod +x /start.sh
# CMD ["/start.sh"]
