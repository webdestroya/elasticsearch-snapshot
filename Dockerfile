FROM gliderlabs/alpine:3.1

MAINTAINER Mitch Dempsey <mitch@mitchdempsey.com>

RUN apk --update add \
    curl \
    jq \
    wget \
    bash

COPY snapshot.sh /snapshot.sh

ENTRYPOINT ["/bin/bash"]

CMD ["/snapshot.sh"]
