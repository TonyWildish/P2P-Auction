#!/bin/sh
./clean.sh

pdflatex 'Bandwidth-sharing in LHCONE: an analysis of the problem.tex'
pdflatex 'Bandwidth-sharing in LHCONE: an analysis of the problem.tex'
open     'Bandwidth-sharing in LHCONE: an analysis of the problem.pdf'
