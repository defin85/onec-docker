ARG DOCKER_REGISTRY_URL
ARG ONEC_VERSION
FROM ${DOCKER_REGISTRY_URL}/onec:${ONEC_VERSION}-server
LABEL maintainer="Anton Kvashenkin <anton.jugatsu@gmail.com> (@jugatsu)"

ARG git_url=https://git.nuk-svk.ru/svk/rac-gui.git
ARG git_branch=master

RUN set -xe \
  && apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      tk8.6 \
      tcl8.6 \
      tk \
      ca-certificates \
      git \
  && rm -rf  \
    /var/lib/apt/lists/* \
    /var/cache/debconf \
  && git clone --depth 1 --branch ${git_branch} ${git_url} /tmp/rac-gui \
  && mkdir -p /usr/share/rac-gui/lib \
  && mkdir -p /usr/share/doc/rac-gui \
  && cp /tmp/rac-gui/lib/*.tcl /usr/share/rac-gui/lib/ \
  && cp -r /tmp/rac-gui/lib/msg /usr/share/rac-gui/lib/ \
  && cp /tmp/rac-gui/rac_gui.cfg /usr/share/rac-gui/ \
  && cp /tmp/rac-gui/rac_gui.png /usr/share/rac-gui/ \
  && cp /tmp/rac-gui/rac_gui.tcl /usr/share/rac-gui/ \
  && echo '#!/bin/sh\nexec tclsh /usr/share/rac-gui/rac_gui.tcl "$@"' > /usr/bin/racgui \
  && chmod +x /usr/bin/racgui \
  && rm -rf /tmp/rac-gui

CMD ["racgui"]
