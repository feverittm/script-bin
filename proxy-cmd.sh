#! /bin/bash

(echo "CONNECT $1:$2 HTTP/1.0"; echo; cat ) | socket web-proxy.cv.hp.com 8088 | (read a; read a; cat )

