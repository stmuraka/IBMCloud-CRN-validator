FROM alpine:latest
MAINTAINER Shaun Murakami (stmuraka@us.ibm.com)
RUN apk update \
 && apk add bash
COPY validate_crn.sh /bin/validate_crn
ENTRYPOINT ["validate_crn"]

