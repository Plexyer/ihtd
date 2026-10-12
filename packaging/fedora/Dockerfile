FROM fedora:44
COPY packaging/fedora/setup.sh /tmp/ihtd-setup.sh
# Optional platform-provided CA for builds behind a trusted HTTPS proxy.
# Supply with --secret id=ihtd_cloud_ca,src=/path/to/platform-ca.crt.
RUN --mount=type=secret,id=ihtd_cloud_ca --mount=type=cache,target=/var/cache/libdnf5 \
    --mount=type=cache,id=ihtd-fedora-tool-downloads,target=/var/cache/ihtd-tools \
    if [ -s /run/secrets/ihtd_cloud_ca ]; then \
      cp /run/secrets/ihtd_cloud_ca /etc/pki/ca-trust/source/anchors/ihtd-cloud.crt && update-ca-trust; \
    fi && bash /tmp/ihtd-setup.sh && dnf clean all
ENV PATH="/opt/flutter/bin:/root/.cargo/bin:${PATH}"
WORKDIR /workspace
COPY . /workspace
CMD ["bash", "packaging/fedora/build.sh"]
