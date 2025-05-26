#!/bin/bash
set -e
kind delete cluster
docker network rm kind
