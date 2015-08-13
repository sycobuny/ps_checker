#############
# ENV setup #
#############
# rbenv/pyenv vars
export RBENV_ROOT    := $(PWD)/vendor/rbenv
export RBENV_VERSION := $(shell cat $(PWD)/.ruby-version)
export PYENV_ROOT    := $(PWD)/vendor/pyenv
export PYENV_VERSION := $(shell cat $(PWD)/.python-version)
export RUBY_DIR      := $(RBENV_ROOT)/versions/$(RBENV_VERSION)
export PYTHON_DIR    := $(PYENV_ROOT)/versions/$(PYENV_VERSION)
export PYTHON_LIBDIR := $(PYTHON_DIR)/lib/python2.7/site-packages

# PostgreSQL vars
export PG_BUILD   := $(PWD)/vendor/postgresql-build
export PG_INSTALL := $(PWD)/vendor/postgresql
export PG_LIBS    := $(PG_INSTALL)/include/server
export PGDATABASE := postgres

# PATH setup
PATH := $(PG_INSTALL)/bin:$(PATH)
PATH := $(PYENV_ROOT)/bin:$(PATH)
PATH := $(RBENV_ROOT)/bin:$(PATH)
PATH := $(PWD)/vendor/ruby-build/bin:$(PATH)
export PATH

# PYTHONPATH setup
export PYTHONPATH := $(PWD)/vendor/pgxnclient

#############################
# OS-specific modifications #
#############################
OS := $(shell uname)
ifeq ($(OS),Darwin)
	CPROG    = cc
	OFLAGS  := -I$(PG_LIBS) -c
	SOFLAGS  = -bundle -flat_namespace -undefined suppress -o
else ifeq ($(OS),Linux)
	CPROG    = cc
	OFLAGS  := -I$(PG_LIBS) -fpic -c
	SOFLAGS  = -shared -o
else ifeq ($(OS),FreeBSD)
	CPROG    = gcc
	OFLAGS  := -I$(PG_LIBS) -fpic -c
	SOFLAGS  = -shared -o
else
	$(error Unknown OS $(OS), cannot make)
endif

#######################
# task target aliases #
#######################
db         := .db/made
ps_checker := $(PG_INSTALL)/lib/ps_checker.so
postgres   := $(PG_INSTALL)
bundler    := $(RUBY_DIR)/bin/bundle
gems       := vendor/ruby
psutil     := $(PYTHON_LIBDIR)/psutil
pgosquery  := $(PYTHON_LIBDIR)/pgosquery-0.0.2-py2.7.egg
pgxn_patch := vendor/pgxnclient/pgxnclient/utils/semver.py.unpatched
multicorn  := $(PG_INSTALL)/share/extension/multicorn.control
ruby       := $(RUBY_DIR)
python     := $(PYTHON_DIR)

################################################
# fixing broken make/shell script interactions #
################################################
# we call any executable which is a shell script with "env" prefixed in front,
# in case there's no punctuation in the command. this is because, for some
# reason, make will try to run shell scripts thus defined without inspecting
# $PATH, or...something. I'm not really sure, but this seems to fix problems.
pyenv      = env pyenv
rbenv      = env rbenv
ruby-build = env ruby-build

################
# Custom tasks #
################
# default task - run this if nothing else is specified
all : \
	$(ps_checker) \
	$(pymodules)  \
	$(multicorn)  \
	$(db)

run :
	$(rbenv) exec bundle exec foreman start

# remove all our working information
clean : \
	clean-db         \
	clean-ps_checker \
	clean-postgres   \
	clean-python     \
	clean-ruby       \
	clean-gems       \
	clean-submodules

######
# db #
######
$(db) : .db $(gems) $(pgosquery)
	$(rbenv) exec bundle exec foreman start -f Procfile.migrate
clean-db :
	rm -rf .db

.db : $(postgres)
	initdb -D .db

##############
# ps_checker #
##############
$(ps_checker) : ps_checker.so
	cp -p ps_checker.so $(PG_INSTALL)/lib/ps_checker.so
clean-ps_checker :
	rm -f ps_checker.so ps_checker.o

ps_checker.so : ps_checker.o
	$(CPROG) $(SOFLAGS) ps_checker.so ps_checker.o

ps_checker.o : $(postgres)
	$(CPROG) $(OFLAGS) ps_checker.c

############
# postgres #
############
$(postgres) : vendor/postgresql-build/.git
	cd $(PG_BUILD) && ./configure --prefix=$(PG_INSTALL)
	$(MAKE) -C $(PG_BUILD) -j8
	$(MAKE) -C $(PG_BUILD) install
clean-postgres :
	rm -rf $(PG_INSTALL)

########
# gems #
########
# call via "env" so make doesn't mess up cause it's a bash script
$(gems) : $(bundler)
	$(rbenv) exec bundle install
clean-gems :
	rm -rf vendor/ruby

# same here re: "env"
$(bundler) : $(ruby)
	$(rbenv) exec gem install bundler

##########
# psutil #
##########
$(psutil) : $(python)
	$(pyenv) exec pip install psutil

#############
# pgosquery #
#############
$(pgosquery) : $(psutil)
	cd vendor/pgosquery && $(pyenv) exec python setup.py install

#############
# multicorn #
#############
$(multicorn) : $(python) $(pgxn_patch)
	cd vendor/pgxnclient && \
		$(pyenv) exec python bin/pgxn install 'multicorn=1.0.4'

$(pgxn_patch) : vendor/pgxnclient/.git
	sed -i.unpatched '128s/.*/    \\-? ([a-z][a-z0-9-]*)?/' \
		vendor/pgxnclient/pgxnclient/utils/semver.py

##########
# python #
##########
$(python) : vendor/pyenv/.git
	PYENV_VERSION=system $(pyenv) install $(PYENV_VERSION)
clean-python :
	rm -rf $(PYTHON_DIR)

########
# ruby #
########
$(ruby) : vendor/ruby-build/.git
	$(ruby-build) $(RBENV_VERSION) $(RUBY_DIR)

clean-ruby :
	rm -rf $(RUBY_DIR)

##############
# submodules #
##############
# define the submodule list
submodules := \
	vendor/pgosquery/.git        \
	vendor/pgxnclient/.git       \
	vendor/postgresql-build/.git \
	vendor/pyenv/.git            \
	vendor/rbenv/.git            \
	vendor/ruby-build/.git

# each submodule gets its own task to init/update the submodule repos
$(submodules) :
	git submodule init
	git submodule update
clean-submodules :
	for dir in `echo "$(submodules)"` ; do \
		( cd `dirname $$dir` && git clean -fdx && git reset --hard HEAD ) ; \
	done

########################
# command-line targets #
########################
# these define targets that someone can use to build certain components
# without having to run the full build process. they are not used internally
# as targets, as they would wind up running extra recipes when not needed.
db : $(db)
	@echo '`make db` complete'
ps_checker : $(ps_checker)
	@echo '`make ps_checker` complete'
postgres : $(postgres)
	@echo '`make postgres` complete'
bundler : $(bundler)
	@echo '`make bundler` complete'
gems : $(gems)
	@echo '`make gems` complete'
psutil : $(psutil)
	@echo '`make psutil` complete'
pgosquery : $(pgosquery)
	@echo '`make pgosquery` complete'
multicorn : $(multicorn)
	@echo '`make multicorn` complete'
ruby : $(ruby)
	@echo '`make ruby` complete'
python : $(python)
	@echo '`make python` complete'
