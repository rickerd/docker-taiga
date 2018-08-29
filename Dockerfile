FROM python:3.5
MAINTAINER Rick de Graaff <rick@rickdegraaff.nl>

ENV DEBIAN_FRONTEND noninteractive

RUN set -x && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        locales \
        gettext \
        ca-certificates \
        nginx \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8 && dpkg-reconfigure locales

COPY taiga-back /usr/src/taiga-back
COPY taiga-front-dist/ /usr/src/taiga-front-dist
COPY docker-settings.py /usr/src/taiga-back/settings/docker.py
COPY conf/locale.gen /etc/locale.gen
COPY conf/nginx/nginx.conf /etc/nginx/nginx.conf
COPY conf/nginx/taiga.conf /etc/nginx/conf.d/default.conf
COPY conf/nginx/ssl.conf /etc/nginx/ssl.conf
COPY conf/nginx/taiga-events.conf /etc/nginx/taiga-events.conf

# Setup symbolic links for configuration files
RUN mkdir -p /taiga
COPY conf/taiga/local.py /taiga/local.py
COPY conf/taiga/conf.json /taiga/conf.json
RUN ln -s /taiga/local.py /usr/src/taiga-back/settings/local.py
RUN ln -s /taiga/conf.json /usr/src/taiga-front-dist/dist/conf.json

# Backwards compatibility
RUN mkdir -p /usr/src/taiga-front-dist/dist/js/ && ln -s /taiga/conf.json /usr/src/taiga-front-dist/dist/js/conf.json

WORKDIR /usr/src/taiga-back

# specify LANG to ensure python installs locals properly
ENV LANG C

RUN pip install --no-cache-dir -r requirements.txt

## Install Slack extension
RUN LC_ALL=C pip install --no-cache-dir taiga-contrib-slack && \
    mkdir -p /usr/src/taiga-front-dist/dist/plugins/slack/ && \
    SLACK_VERSION=$(pip show taiga-contrib-slack | awk '/^Version: /{print $2}') && \
    echo "taiga-contrib-slack version: $SLACK_VERSION" && \
    curl https://raw.githubusercontent.com/taigaio/taiga-contrib-slack/$SLACK_VERSION/front/dist/slack.js -o /usr/src/taiga-front-dist/dist/plugins/slack/slack.js && \
    curl https://raw.githubusercontent.com/taigaio/taiga-contrib-slack/$SLACK_VERSION/front/dist/slack.json -o /usr/src/taiga-front-dist/dist/plugins/slack/slack.json

RUN echo "LANG=en_US.UTF-8" > /etc/default/locale
RUN echo "LC_TYPE=en_US.UTF-8" > /etc/default/locale
RUN echo "LC_MESSAGES=POSIX" >> /etc/default/locale
RUN echo "LANGUAGE=en" >> /etc/default/locale

RUN echo "LANG=en_US.UTF-8" >> /etc/default/locale && \
    echo "LC_ALL=en_US.UTF-8" >> /etc/default/locale && \
    echo "LC_TYPE=en_US.UTF-8" >> /etc/default/locale && \
    echo "LC_MESSAGES=POSIX" >> /etc/default/locale && \
    echo "LANGUAGE=en" >> /etc/default/locale

ENV LANG en_US.UTF-8
ENV LC_TYPE en_US.UTF-8

RUN locale-gen en_US.UTF-8 && locale -a

ENV TAIGA_SSL False
ENV TAIGA_ENABLE_EMAIL False
ENV TAIGA_HOSTNAME localhost
ENV TAIGA_SECRET_KEY "!!!REPLACE-ME-j1598u1J^U*(y251u98u51u5981urf98u2o5uvoiiuzhlit3)!!!"
ENV TAIGA_SSL_BY_REVERSE_PROXY False

RUN python manage.py collectstatic --noinput

RUN locale -a

# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80 443

VOLUME /usr/src/taiga-back/media

# Static file serving
HEALTHCHECK CMD curl --fail http://localhost:80/conf.json || exit 1

COPY checkdb.py /checkdb.py
COPY docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["gunicorn", "-w 3", "-t 60", "--pythonpath=.", "-b 0.0.0.0:8000", "taiga.wsgi"]
