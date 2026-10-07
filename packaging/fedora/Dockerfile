FROM fedora:44
COPY packaging/fedora/setup.sh /tmp/ihtd-setup.sh
RUN bash /tmp/ihtd-setup.sh && dnf clean all
ENV PATH="/opt/flutter/bin:/root/.cargo/bin:${PATH}"
WORKDIR /workspace
COPY . /workspace
CMD ["bash", "packaging/fedora/build.sh"]
