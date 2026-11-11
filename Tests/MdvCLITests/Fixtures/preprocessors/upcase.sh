#!/bin/sh
# Well behaved: reads all of stdin, writes it upper-cased.
exec tr '[:lower:]' '[:upper:]'
