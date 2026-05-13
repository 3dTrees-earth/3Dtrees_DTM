FROM rocker/geospatial:4.5
SHELL ["/bin/bash", "-c"]

RUN R -e "install.packages(c('argparse', 'lidR', 'terra', 'RCSF', 'future'))"

RUN mkdir -p /in /out /src && chmod 777 /in /out /src
COPY src /src
RUN chmod 755 /src && chmod 644 /src/*.R

WORKDIR /src
CMD ["Rscript", "run.R", "--help"]
