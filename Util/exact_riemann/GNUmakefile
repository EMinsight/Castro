PRECISION  = DOUBLE
PROFILE    = FALSE

DEBUG      = FALSE

DIM        = 3

COMP	   = gnu

USE_MPI    = FALSE
USE_OMP    = FALSE

USE_ALL_CASTRO = FALSE
USE_AMR_CORE = FALSE

# define the location of the CASTRO top directory
CASTRO_HOME  ?= ../..

# This sets the EOS directory in Castro/EOS
EOS_DIR     := helmholtz

# This sets the network directory in Castro/Networks
NETWORK_DIR := general_null
NETWORK_INPUTS = ignition.net

EXTERN_SEARCH += .

Bpack   := ./Make.package
Blocs   := .

include $(CASTRO_HOME)/Exec/Make.Castro
