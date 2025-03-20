#!/bin/bash

cd /.btrfsroot/

mv @ "@-rollback-$(date)"

btrfs su snapshot /.snapshots/$1/snapshot/ @

btrfs su set-default @

