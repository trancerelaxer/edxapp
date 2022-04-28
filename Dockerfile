FROM ubuntu:focal as base
ARG SETTINGS_MODULE=assets
ENV LC_ALL en_US.UTF-8

RUN mkdir -p /openedx/edx-platform
WORKDIR /openedx/edx-platform
COPY ./ .
RUN apt-get update -yqq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -yqq \
    build-essential \
    curl \
    g++ \
    gcc \
    git \
    git-core \
    language-pack-en \
    libfreetype6-dev \
    libmysqlclient-dev \
    libssl-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libxslt1-dev \
    swig \
    gettext \
    gfortran \
    graphviz \
    libffi-dev \
    libfreetype6-dev \
    libgeos-dev \
    libgraphviz-dev \
    libjpeg8-dev \
    liblzma-dev \
    liblapack-dev \
    libpng-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libxslt1-dev \
    lynx \
    ntp \
    pkg-config \
    python-openssl \
    python3-dev python3.8 python3-pip \
    python3-venv \
    rdfind \
    tk-dev \
    xz-utils \
    && rm -rf /var/lib/apt/lists/* && rm -rf .git && apt-get -yqq autoclean && apt-get -yqq autoremove

ARG OPENEDX_I18N_VERSION=open-release/maple.master

RUN curl -Lo openedx-i18n.tar.gz https://github.com/openedx/openedx-i18n/archive/$OPENEDX_I18N_VERSION.tar.gz \
    && tar xzf openedx-i18n.tar.gz \
    && mkdir -p /openedx/locale/contrib \
    && mv openedx-i18n-*/edx-platform/locale /openedx/locale/contrib \
    && rm -rf openedx-i18n*

ENV PATH /opt/nodeenv/bin:${PATH}
ENV PATH ./node_modules/.bin:${PATH}

RUN git config --global url."https://".insteadOf git:// && ln -s /usr/bin/python3 /usr/bin/python && \
    python3 -m pip install --quiet -r requirements/pip.txt nodeenv==1.6.0 django-redis==4.12.1 uwsgi==2.0.20 Paver==1.3.4 -r requirements/edx/base.txt  django-debug-toolbar factory-boy  && \
    python3 ./common/lib/xmodule/xmodule/static_content.py ./common/static/xmodule && \
    nodeenv /opt/nodeenv --node=12.13.0 --prebuilt

COPY ./themes/ /openedx/themes/

FROM base as nodejs_dependencies

ENV NO_PREREQ_INSTALL=True
ARG SETTINGS_MODULE=assets
ENV STATIC_ROOT_LMS=/openedx/staticfiles
ENV STATIC_ROOT_CMS=/openedx/staticfiles/studio
ENV NODE_ENV=prod

RUN npm install && npm install jquery.scrollto@2.1.2 && \
    paver update_assets --settings=assets --skip-collect  && \
    STATIC_ROOT_LMS=/openedx/staticfiles STATIC_ROOT_CMS=/openedx/staticfiles/studio  ./node_modules/.bin/webpack  --progress --config=webpack.prod.config.js && \
    python3 manage.py lms --settings=${SETTINGS_MODULE} compile_sass  common && \
    for i in cms lms; do python3 manage.py $i --settings=${SETTINGS_MODULE} compile_sass  --theme-dirs="./themes" --themes dark-theme edge.edx.org edx.org open-edx red-theme stanford-style; done && \ 
    python3 manage.py lms --settings=${SETTINGS_MODULE} collectstatic --ignore "fixtures" \
                                                                      --ignore "karma_*.js" \
                                                                      --ignore "spec" \
                                                                      --ignore "spec_helpers" \
                                                                      --ignore "spec-helpers" \
                                                                      --ignore "xmodule_js" \
                                                                      --ignore "geoip" \
                                                                      --ignore "sass" --noinput && \
    python3 manage.py cms --settings=${SETTINGS_MODULE} collectstatic --ignore "fixtures" \
                                                                      --ignore "karma_*.js" \
                                                                      --ignore "spec" \
                                                                      --ignore "spec_helpers" \
                                                                      --ignore "spec-helpers" \
                                                                      --ignore "xmodule_js" \
                                                                      --ignore "geoip" \
                                                                      --ignore "sass" --noinput && \
    python3 manage.py cms --settings=${SETTINGS_MODULE} compilejsi18n && \
    python3 manage.py lms --settings=${SETTINGS_MODULE} compilejsi18n && \
    rdfind -makesymlinks true -followsymlinks true /openedx/staticfiles/

FROM base AS release

COPY --from=nodejs_dependencies /openedx/staticfiles/ /openedx/staticfiles/
ARG USERID=1000
RUN useradd --home-dir /openedx -u $USERID openedx && chown -R openedx /openedx && rm -rf node_modules && \
    mkdir -p /edx /openedx/data/logs && chmod -R 777 /edx /openedx/data/logs && chown -R openedx /edx && chown -R openedx /openedx/data/logs
USER openedx

ENV SERVICE_VARIANT=lms
ENV DJANGO_SETTINGS_MODULE=${SERVICE_VARIANT}.envs.production

CMD uwsgi \
  --static-map /static=/openedx/staticfiles/ \
  --static-map /media=/openedx/media/ \
  --http 0.0.0.0:8000 \
  --thunder-lock \
  --single-interpreter \
  --enable-threads \
  --processes=${UWSGI_WORKERS:-2} \
  --buffer-size=8192 \
  --wsgi-file ${SERVICE_VARIANT}/wsgi.py
