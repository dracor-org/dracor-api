xquery version "3.1";

import module namespace config = "http://dracor.org/ns/exist/v0/config"
  at "modules/config.xqm";

(: The following external variables are set by the repo:deploy function :)
(: the target collection into which the app is deployed :)
declare variable $target external;

declare function local:store ($file-path, $content) {
  let $segments := tokenize($file-path, '/')
  let $name := $segments[last()]
  let $col := substring($file-path, 1, string-length($file-path) - string-length($name) - 1)
  return xmldb:store($col, $name, $content)
};

(: We create an initial config file the values of which can be passed by the
 : following environment variables:
 :
 : - DRACOR_API_BASE: base URI the DraCor API will be available under
 : - FUSEKI_SERVER: base URI of the fuseki server
 : - METRICS_SERVER: DraCor metrics service URI
 :)
declare function local:create-config-file ()
as item()? {
  if(doc($config:file)/config) then
    ()
  else (
    util:log-system-out("Creating " || $config:file),
    local:store(
      $config:file,
      <config>
        <api-base>
        {
          if (environment-variable("DRACOR_API_BASE")) then
            environment-variable("DRACOR_API_BASE")
          else "https://dracor.org/api/v0"
        }
        </api-base>
        <services>
          <fuseki>
          {
            if (environment-variable("FUSEKI_SERVER")) then
              environment-variable("FUSEKI_SERVER")
            else "http://localhost:3030/dracor/"
          }
          </fuseki>
          <metrics>
          {
            if (environment-variable("METRICS_SERVER")) then
              environment-variable("METRICS_SERVER")
            else "http://localhost:8030/metrics/"
          }
          </metrics>
        </services>
      </config>
    )
  )
};

(: We create an initial config file the values of which can be passed by the
 : following environment variables:
 :
 : - GITHUB_WEBHOOK_SECRET: secret for the GitHub webhook
 : - FUSEKI_SECRET: admin password for the fuseki server
 :)
declare function local:create-secrets-file ()
as item()? {
  if(doc($config:secrets-file)/secrets) then
    ()
  else (
    util:log-system-out("Creating " || $config:secrets-file),
    local:store(
      $config:secrets-file,
      <secrets>
        <fuseki>{environment-variable("FUSEKI_SECRET")}</fuseki>
        <gh-webhook>{environment-variable("GITHUB_WEBHOOK_SECRET")}</gh-webhook>
      </secrets>
    ),
    (: FIXME: find a better solution to protect the webhook secret :)
    sm:chmod(xs:anyURI($config:secrets-file), 'rw-------')
  )
};

(: elevate privileges for github webhook :)
let $webhook := xs:anyURI($target || '/modules/webhook.xqm')
let $sitelinks-job := xs:anyURI($target || '/jobs/sitelinks.xq')

(: register the RESTXQ module :)
let $restxq-module := xs:anyURI('modules/api.xpm')

return (
  local:create-config-file(),
  local:create-secrets-file(),
  sm:chown($webhook, "admin"),
  sm:chgrp($webhook, "dba"),
  sm:chmod($webhook, 'rwsr-xr-x'),
  sm:chown($sitelinks-job, "admin"),
  sm:chgrp($sitelinks-job, "dba"),
  sm:chmod($sitelinks-job, 'rwsr-xr-x'),
  exrest:register-module($restxq-module),

  (: a note on using the RDF index :)
  util:log-system-out(
    "To use the RDF index the database needs to be restarted. "
  )
)
