# Documentation about the build process

## Overview

The basic build process involves the following tasks:

- `make env`: This makes sure the development environment is properly
  configured.
  - Part of this is to add the `ModelicaByExample` directory to the OpenModelica
    library path. Normally, it should be possible to simply add the
    `ModelicaByExample` directory to the `MODELICAPATH` using the
    `setModelicaPath(getModelicaPath()+":"+...);` commands (which are still
    present in the `.mos` files). But I couldn't get this to work properly so I
    resorted to just symlinking them into the directory that OpenModelica
    searches.
  - Another step is just ensuring that the `.dvc/cache` directory exists.
  - Finally, we populate the contents `text/build-arch` with the output `uname
-m`. This is to ensure that any artifacts managed by DVC take the platform
    into account.
- `make specs`: This creates the various `.mos` files used to compile models.
  It also creates the `dvc.yaml` file that includes the "experiments" that need
  to be run by `dvc`. This includes information about the inputs and outputs to
  each of these experiments so that `dvc` can manage the artifacts associated
  with them in its "run cache".
- `make results`: This creates the executable file associated with each "case"
  along with the `_info.json`, `_init.xml` and `_res.mat` files associated with
  that case. It is this target that invokes `dvc`.
- `make pdfs`: This builds both the Letter and A4 PDF files. Note that this
  command will ensure that the `specs` and `results` targets are invoked.
- `make json`: This creates the content needed by the book web site (see next
  section).

## Book Site

The book site is a web application. It has its own build process. It depends
on the artifacts created by the `make json` command discussed above. That
target creates JSON represenations of book content. But the material first
needs to be copied into the `nextgen` directory.

When copying files, you need to copy the files associated with the language you
are interested in. So to copy the English language files, use:

```
make copy_en_files
```

Likewise, to copy the Korean files, use

```
make_kr_files
```

Once the files are in place, we can either preview the site or generate the
static files required. To preview, run `make preview`. To generate static
files to be published, _e.g._, on Netlify, use `make publish`. Note that
this only creates the directory where the static files will be stored, it
does not upload them anywhere.

## Source Code

To ensure all submodules are loaded, be sure to run:

```sh
$ git submodule init
$ git submodule update
```

## `dvc`

I'm using `dvc` to "cache" the results of certain build steps. Specifically,
simulation of models. What `dvc` does is to check dependencies based on
content, not dates (like `make`). As such, it maintains a "run cache" in
`.dvc/cache` that records the outputs of running the various `build-case-XXX`
stages in `text/dvc.yaml` (which is itself generated by the `make specs`) build
step.

The result of all this is that if the simulation script `XXX.mos` is the same
and it has been run for the current `ModelicaByExample` package on the same
architecture (as indicated by the `build-arch` file created by `make env`), then
`dvc` detects this and simply fetches the generated artifacts rather than run
the simulation again.

I have noticed some odd behavior with `dvc` when running inside a container.
But it appears the behavior is really due to `omc`. For some reason, on my M1
Mac running in a devcontainer, `omc` sometimes takes a very long time to
simulate and ultimately exits with a -9 status code. I don't know why this is.
But I find that if I avoid using `make` and simply go to the `text` directory
and run `dvc repro` it will sometimes get through. Once it has run all these
simulations and the run cache has all the necessary artifacts, this is no longer
a problem (since `dvc` just fetches the artifacts from the cache).

## Docker Images

### New Way

I'm now using devcontainers (in VS Code) and I'll be updating the Gitlab CI/CD
pipelines soon. The images I'm using are much newer and are created by the
OpenModelica team themselves (including ARM images!).

### Docker on Macs

I'm currently using [`colima`](https://github.com/abiosoft/colima/) to support
Docker devcontainers on Mac. I installed it with `homebrew install colima`.

To start, run `colima start`. After that, normal `docker` commands should work
and VS Code should be able to use those tools to spawn devcontainers. On my
system, generating the results requires more memory so you can either start
`colima` with `colima start --memory 8` or you can run `colima template` and
change the template to allocate 8Gb of memory.

### Multi-Platform Builds

To do a multi-platform build, I first needed to install `buildx` (see
[here](https://github.com/abiosoft/colima/discussions/273)). From there, I just
looked at [some
examples](https://www.docker.com/blog/multi-arch-build-what-about-gitlab-ci/)
and came up with:

```
$ docker buildx create --use
$ docker buildx build . --platform linux/arm64/v8,linux/amd64 -t registry.gitlab.com/michael.tiller/modelicabook:v0.1.2
```

This could also be done via the CI/CD system if the `Dockerfile` were kept in a
different repository.

### Locale

I also needed to define `LC_ALL` as follows within Docker containers:

```
$ export LC_ALL=C
```

But in addition, I found the containers were missing the necessary locales. So to get then `en` locale, I have to also run:

```
$ sudo apt-get install language-pack-en
```

### Building Base Image

To create the base image, go to the `.devcontainer` directory and run:

```
$ docker login registry.gitlab.com
$ docker build . -t registry.gitlab.com/michael.tiller/modelicabook:vX.Y.Z
$ docker push registry.gitlab.com/michael.tiller/modelicabook:vX.Y.Z
```

### Old Way

These steps are designed to be performed by the `mtiller/book-builder` image.
To run this on an M1 Mac, run:

```sh
$ docker run -it --platform=linux/amd64 -v `pwd`:/opt/MBE/ModelicaBook mtiller/book-builder
```

or

```sh
$ docker run -it --platform=linux/amd64 -v `pwd`:/opt/MBE/ModelicaBook mtiller/flat-book-builder
```

...if you get lots of warnings about long file names.

## Step 1: Build Simulation Specifications

_Dependencies_: `text/specs.py`, `text/spec-hash` and Python

_Image_: `mtiller/book-builder` or `python:2.7.12` + `pip install jinja2`

_Artifacts_: `text/results/Makefile`, `text/results/json/*.json`,
`text/results/*.mos` and `text/plots/*.py`

_Job_: `make specs`

In this step, we collect information about the different "cases" we need to
present in the book. The actual cases are outlined in `text/specs.py`. This is
a largely declarative listing of the use cases.

Execution of this script produces the following files:

- The `text/results/Makefile` which defines how to build all simulations and
  their associated results.
- A `json` encoded representation of each case in `text/results/json/<CaseId>-case.json`.
- A script to build and simulation each individual case in `text/results/<CaseId>.mos`.
- A Python script to generate the plots for each case in `text/plots/<CaseId>.py`.

**NB**: The hash of the `text/specs.py` file is stored in the file
`text/spec-hash` and is used in the Makefile to determine if this step can be
skipped because the generated files out be identical to a previous run.

## Step 2: Build Simulation Results

_Dependencies_: Artifacts from running `text/specs.py`, `text/result-hash` and **`omc`**

_Image_: `mtiller/book-builder` (works on M1 if you run over and over) or perhaps `openmodelica/openmodelica:v1.17.0-minimal` (but not on M1)

_Artifacts_: `text/results/{executables,*_info.json,*_init.xml/*_res.mat}`

_Job_: `make results`

This step uses the OpenModelica compiler to build the following files for each
case defined in step 1.

- An executable for each case in `text/results/<CaseId>`.
- An "info" file generated by OpenModelica about each case in `text/results/<CaseId>_info.json`
- An initialization file in `text/results/<CaseId>_init.xml`
- A simulation result in `text/results/<CaseId>_res.mat`

The executables and init files are stored in `exes.tar.gz` (which is also used
by the simulation server API).

**NB**: The hash of the `ModelicaByExample` directory combined with the hash of
the `text/specs.py` file are stored in the file `text/results-hash` and is used
in the `text/Makefile` to determine if this step can be skipped because the
generated files out be identical to a previous run.

## Step 3: Build JSON (used by site generator)

_Dependencies_: `text/results/*.mos` and `text/plots/*.py` (guess)

_Image_: `mtiller/book-builder` or `sphinxdoc/sphinx` + `pip install matplotlib`

_Artifacts_: `text/build/json`

_Job_: `make json` or just `sphinx-build -b json -d build/doctrees  -q source build/json`

This generats the JSON output for the book. This includes HTML embedded in the
JSON. These files are required for the next step which is to translate the JSON
data into the book site.

## Step 4: Generating Site

???

## Step 5: Generate PDFs

_Dependencies_: `text/results/*.mos` and `text/plots/*.py` (guess)

_Image_: `mtiller/book-builder` or `sphinxdoc/sphinx` + `pip install matplotlib`

_Artifacts_: `text/build/latex`

_Job_: `make latex` (?) or just `sphinx-build -b latex -d build/doctrees  -q source build/latex`

## Step 6: Generate eBooks

## Step 7: Generate HTML (deprecated, don't need this)

## Step 8: Deploying Site

I'm using `now` to do the site deployment. Much simpler than all that mucking
about with AWS S3, IAM, permissions, keys, _etc._

It can also be published as a simple Docker image. All that is required is to
generate the files from Next and then wrap them in an NGINX container.

## Step 9: Build and Deploy API

_Dependencies_: `text/results/exes.tar.gz`

_Image_: `node` and `docker`

_Artifacts_: Docker image

_Job_: (see `.gitlab-ci.yaml`)
