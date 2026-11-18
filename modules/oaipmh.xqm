xquery version "3.1";

(:~
 : DraCor implementation of the Open Archives Initiative Protocol for Metadata
 : Harvesting (OAI-PMH) 2.0
 :
 : See https://www.openarchives.org/OAI/openarchivesprotocol.html
 :
 : The items of the repository are the DraCor corpora, one record per corpus.
 : Records are disseminated as Dublin Core (`oai_dc`) and as CMDI 1.2 (`cmdi`)
 : using the CLARIN collection profile, so that the corpora can be harvested
 : by the CLARIN Virtual Language Observatory (VLO).
 :
 : The datestamp of a record is the time the corpus was last (re)loaded, i.e.
 : the modification time of its `git.xml` (falling back to `corpus.xml`). It
 : does not change when only the code generating the records changes, so
 : incremental harvests (`from`) miss such changes until the corpus is loaded
 : again; with one record per corpus a full harvest is cheap. Conversely, a
 : fresh deployment that reloads the corpora resets all datestamps.
 :
 : The languages of a corpus are derived from `TEI/@xml:lang` of its plays and
 : normalized to ISO 639-3, ordered by the number of plays.
 :
 : The repository supports neither sets nor deleted records, and with one
 : record per corpus no flow control (resumption tokens) is needed.
 :
 : Known limitation: arguments not defined by OAI-PMH (e.g. `foo=bar`) are
 : ignored instead of being answered with `badArgument`. RESTXQ only passes the
 : declared parameters, and eXist provides no request object in a RESTXQ
 : context to list the others.
 :)
module namespace dpmh = "http://dracor.org/ns/exist/v1/oai-pmh";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace xsi = "http://www.w3.org/2001/XMLSchema-instance";
declare namespace oai = "http://www.openarchives.org/OAI/2.0/";
declare namespace oai_dc = "http://www.openarchives.org/OAI/2.0/oai_dc/";
declare namespace dc = "http://purl.org/dc/elements/1.1/";
declare namespace cmd = "http://www.clarin.eu/cmd/1";
declare namespace cmdp = "http://www.clarin.eu/cmd/1/profiles/clarin.eu:cr1:p_1345561703620";

import module namespace config = "http://dracor.org/ns/exist/v1/config" at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util" at "util.xqm";
import module namespace iso639 = "http://dracor.org/ns/exist/v1/iso639" at "iso639.xqm";

declare variable $dpmh:base-url := $config:api-base || "/oai";

declare variable $dpmh:repository-name := "DraCor – Drama Corpora Project";

declare variable $dpmh:admin-email := "info@dracor.org";

(: host of the identifier base, e.g. dracor.org :)
declare variable $dpmh:repository-id := replace(
  $config:id-base,
  "^https?://([^/:]+).*$",
  "$1"
);

(: prefix of OAI identifiers, e.g. oai:dracor.org: :)
declare variable $dpmh:id-prefix := "oai:" || $dpmh:repository-id || ":";

declare variable $dpmh:granularity := "YYYY-MM-DDThh:mm:ssZ";

declare variable $dpmh:cmdi-profile := "clarin.eu:cr1:p_1345561703620";

declare variable $dpmh:formats := map {
  "oai_dc":
    map {
      "schema": "http://www.openarchives.org/OAI/2.0/oai_dc.xsd",
      "namespace": "http://www.openarchives.org/OAI/2.0/oai_dc/"
    },
  "cmdi":
    map {
      "schema": "https://infra.clarin.eu/CMDI/1.x/xsd/cmd-envelop.xsd",
      "namespace": "http://www.clarin.eu/cmd/1"
    }
};

(: arguments allowed for each verb (besides `verb` itself) :)
declare variable $dpmh:verbs := map {
  "Identify": (),
  "ListMetadataFormats": ("identifier"),
  "ListSets": ("resumptionToken"),
  "ListIdentifiers":
    ("metadataPrefix", "from", "until", "set", "resumptionToken"),
  "ListRecords": ("metadataPrefix", "from", "until", "set", "resumptionToken"),
  "GetRecord": ("identifier", "metadataPrefix")
};

declare variable $dpmh:arguments := (
  "verb",
  "identifier",
  "metadataPrefix",
  "from",
  "until",
  "set",
  "resumptionToken"
);

(:
 : --------------------
 : Helpers
 : --------------------
 :)

(:~
 : Format a dateTime as UTC datestamp, e.g. 2026-11-06T10:15:00Z
 :)
declare function dpmh:utc($dt as xs:dateTime) as xs:string {
  format-dateTime(
    adjust-dateTime-to-timezone($dt, xs:dayTimeDuration("PT0S")),
    "[Y0001]-[M01]-[D01]T[H01]:[m01]:[s01]Z"
  )
};

(:~
 : Strip the Markdown links and emphasis produced by dutil:get-corpus-info
 : from a description.
 :)
declare function dpmh:plain-text($text as xs:string) as xs:string {
  $text
    => replace("\[([^\]]*)\]\(([^)]*)\)", "$1 ($2)")
    => replace("\*\*([^*]*)\*\*", "$1")
};

(:~
 : All corpora as maps with the information needed for OAI records, ordered by
 : name.
 :)
declare function dpmh:corpora() as map(*)* {
  (: DEPRECATED: remove teiCorpus support in v2 :)
  for $corpus in
    collection($config:corpora-root)/(tei:dracorCorpus | tei:teiCorpus)
  let $info := dutil:get-corpus-info($corpus)
  order by $info?name
    (: no `where` clause referring to $info, eXist fails to evaluate it :)
  return if ($info?name) then
    map:merge(
      (
        $info,
        map:entry("identifier", $dpmh:id-prefix || $info?name),
        map:entry("datestamp", dpmh:datestamp($corpus)),
        map:entry("languages", dpmh:languages($corpus)),
        dpmh:doi($corpus)!map:entry("doi", .)
      )
    )
  else (
  )
};

(:~
 : Concept DOI of a corpus from `publicationStmt/idno[@type="DOI"]` in
 : corpus.xml (see dracor-org/dracor-schema#207), as bare DOI without resolver
 : or `doi:` prefix. The type is matched case-insensitively until the schema
 : decision is made.
 :)
declare function dpmh:doi($corpus as element()) as xs:string? {
  let $idno := $corpus/tei:teiHeader//tei:publicationStmt/tei:idno[lower-case(
    @type
  ) eq
    "doi"][normalize-space()][1]
  return $idno!replace(
    normalize-space(.),
    "^(https?://(dx\.)?doi\.org/|doi:)",
    "",
    "i"
  )
};

(:~
 : ISO 639-3 codes of the languages of the plays in a corpus (from
 : `TEI/@xml:lang`), the most frequent first. Unrecognized codes are skipped.
 :)
declare function dpmh:languages($corpus as element()) as xs:string* {
  let $codes := collection(
    util:collection-name($corpus)
  )/tei:TEI/@xml:lang!iso639:to-639-3(string(.))
  for $code in distinct-values($codes)
  order by count($codes[. eq $code]) descending, $code
  return $code
};

(:~
 : Datestamp of a corpus: the last modification of its git.xml (written when
 : the corpus is loaded or updated), falling back to the corpus document.
 :)
declare function dpmh:datestamp($corpus as element()) as xs:string {
  let $collection := util:collection-name($corpus)
  let $dt := (
    if (doc-available($collection || "/git.xml")) then
      xmldb:last-modified($collection, "git.xml")
    else (
    ),
    xmldb:last-modified($collection, util:document-name($corpus))
  )[1]
  return dpmh:utc($dt)
};

(:~
 : Parse a from/until argument.
 :
 : @return map with the dateTime ("value") and granularity ("day" or
 : "seconds"), or empty sequence if the argument is not a valid UTCdatetime
 :)
declare function dpmh:parse-date(
  $value as xs:string,
  $until as xs:boolean
) as map(*)? {
  if (
    matches($value, "^\d{4}-\d{2}-\d{2}$") and $value castable as xs:date
  ) then
    map {
      "value":
        xs:dateTime(
          $value ||
            (
              if ($until) then
                "T23:59:59Z"
              else
                "T00:00:00Z"
            )
        ),
      "granularity": "day"
    }
  else if (
    matches($value, "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$") and
      $value castable as xs:dateTime
  ) then
    map {"value": xs:dateTime($value), "granularity": "seconds"}
  else (
  )
};

(:
 : --------------------
 : Response building
 : --------------------
 :)

(:~
 : Wrap the verb specific content into the OAI-PMH response envelope.
 :
 : @param $args Map of request arguments; empty for badVerb and badArgument
 : errors, in which case the request element must not carry attributes.
 : @param $content Verb element or error elements
 :)
declare function dpmh:response(
  $args as map(*),
  $content as element()*
) as element(oai:OAI-PMH) {
  <OAI-PMH
    xmlns="http://www.openarchives.org/OAI/2.0/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd"
  >
    <responseDate>{ dpmh:utc(current-dateTime()) }</responseDate>
    <request>
      {
        for $key in map:keys($args)
        order by index-of($dpmh:arguments, $key)
        return attribute {$key} { $args($key) }
      }
      { $dpmh:base-url }
    </request>
    { $content }
  </OAI-PMH>
};

declare function dpmh:error(
  $code as xs:string,
  $message as xs:string
) as element(oai:error) {
  <error xmlns="http://www.openarchives.org/OAI/2.0/" code="{ $code }">
    { $message }
  </error>
};

declare function dpmh:header($corpus as map(*)) as element(oai:header) {
  <header xmlns="http://www.openarchives.org/OAI/2.0/">
    <identifier>{ $corpus?identifier }</identifier>
    <datestamp>{ $corpus?datestamp }</datestamp>
  </header>
};

declare function dpmh:record(
  $corpus as map(*),
  $prefix as xs:string
) as element(oai:record) {
  <record xmlns="http://www.openarchives.org/OAI/2.0/">
    { dpmh:header($corpus) }
    <metadata>
      {
        if ($prefix = "cmdi") then
          dpmh:cmdi($corpus)
        else
          dpmh:oai-dc($corpus)
      }
    </metadata>
  </record>
};

(:~
 : URLs related to a corpus
 :)
declare function dpmh:links($corpus as map(*)) as map(*) {
  let $name := $corpus?name
  (: a branch may be given as fragment, e.g. https://github.com/org/repo#main :)
  let $repo := $corpus?repository!replace(., "#.*$", "")
  let $branch := $corpus?repository[contains(., "#")]!substring-after(., "#")
  (: link the loaded commit, or else at least the loaded branch :)
  let $ref := ($corpus?commit, $branch)[.][1]
  let $sha := $corpus?commit
  let $is-github := starts-with($repo, "https://github.com/")
  return map {
    "uri": dutil:corpus-uri($name),
    "doi": $corpus?doi!("https://doi.org/" || .),
    "landing-page": $config:api-origin || "/" || $name,
    "api": $config:api-base || "/corpora/" || $name,
    "api-metadata": $config:api-base || "/corpora/" || $name || "/metadata",
    "dts":
      $config:api-base ||
        "/dts/collection?id=" ||
        encode-for-uri(dutil:corpus-uri($name)),
    "repository":
      if ($repo and $ref and $is-github) then
        $repo || "/tree/" || $ref
      else
        $repo,
    "zip":
      if ($repo and $sha and $is-github) then
        $repo || "/archive/" || $sha || ".zip"
      else (
      )
  }
};

(:
 : --------------------
 : Metadata formats
 : --------------------
 :)

(:~
 : Dublin Core record of a corpus
 :)
declare function dpmh:oai-dc($corpus as map(*)) as element(oai_dc:dc) {
  let $links := dpmh:links($corpus)
  return <oai_dc:dc
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/oai_dc/ http://www.openarchives.org/OAI/2.0/oai_dc.xsd"
  >
    <dc:title>{ $corpus?title }</dc:title>
    <dc:title>{ $corpus?acronym }</dc:title>
    <dc:publisher>DraCor</dc:publisher>
    {
      if ($corpus?description) then
        <dc:description>
          { dpmh:plain-text($corpus?description) }
        </dc:description>
      else (
      )
    }
    <dc:type>Collection</dc:type>
    <dc:type>Text</dc:type>
    { $corpus?languages!<dc:language>{ . }</dc:language> }
    <dc:format>application/tei+xml</dc:format>
    { $links?doi!<dc:identifier>{ . }</dc:identifier> }
    <dc:identifier>{ $links?uri }</dc:identifier>
    <dc:identifier>{ $links?landing-page }</dc:identifier>
    {
      for $rel in ($links?repository, $links?api)
      return <dc:relation>{ $rel }</dc:relation>
    }
    {
      if ($corpus?commit) then
        <dc:description>
          { "Version: Git commit " || $corpus?commit }
        </dc:description>
      else (
      )
    }
    {
      for $rights in ($corpus?licence, $corpus?licenceUrl)
      return <dc:rights>{ $rights }</dc:rights>
    }
  </oai_dc:dc>
};

(:~
 : CMDI 1.2 record of a corpus using the CLARIN collection profile
 : (clarin.eu:cr1:p_1345561703620)
 :)
declare function dpmh:cmdi($corpus as map(*)) as element(cmd:CMD) {
  let $links := dpmh:links($corpus)
  let $self := $dpmh:base-url ||
    "?verb=GetRecord&amp;metadataPrefix=cmdi&amp;identifier=" ||
    encode-for-uri($corpus?identifier)
  return <cmd:CMD
    xmlns:cmd="http://www.clarin.eu/cmd/1"
    xmlns:cmdp="http://www.clarin.eu/cmd/1/profiles/clarin.eu:cr1:p_1345561703620"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    CMDVersion="1.2"
    xsi:schemaLocation="http://www.clarin.eu/cmd/1 https://infra.clarin.eu/CMDI/1.x/xsd/cmd-envelop.xsd http://www.clarin.eu/cmd/1/profiles/clarin.eu:cr1:p_1345561703620 https://catalog.clarin.eu/ds/ComponentRegistry/rest/registry/1.x/profiles/clarin.eu:cr1:p_1345561703620/xsd"
  >
    <cmd:Header>
      <cmd:MdCreator>DraCor API</cmd:MdCreator>
      <cmd:MdCreationDate>
        { substring($corpus?datestamp, 1, 10) }
      </cmd:MdCreationDate>
      <cmd:MdSelfLink>{ $self }</cmd:MdSelfLink>
      <cmd:MdProfile>{ $dpmh:cmdi-profile }</cmd:MdProfile>
      <cmd:MdCollectionDisplayName>
        { $corpus?acronym }
      </cmd:MdCollectionDisplayName>
    </cmd:Header>
    <cmd:Resources>
      <cmd:ResourceProxyList>
        <cmd:ResourceProxy id="{ $corpus?name }-landing-page">
          <cmd:ResourceType mimetype="text/html">LandingPage</cmd:ResourceType>
          <cmd:ResourceRef>{ $links?landing-page }</cmd:ResourceRef>
        </cmd:ResourceProxy>
        {
          if ($links?zip) then
            <cmd:ResourceProxy id="{ $corpus?name }-tei-zip">
              <cmd:ResourceType
                mimetype="application/zip"
              >Resource</cmd:ResourceType>
              <cmd:ResourceRef>{ $links?zip }</cmd:ResourceRef>
            </cmd:ResourceProxy>
          else (
          )
        }
        {
          (: the DOI identifies the corpus archived on Zenodo (all versions) :)
          if ($links?doi) then
            <cmd:ResourceProxy id="{ $corpus?name }-doi">
              <cmd:ResourceType>Resource</cmd:ResourceType>
              <cmd:ResourceRef>{ $links?doi }</cmd:ResourceRef>
            </cmd:ResourceProxy>
          else (
          )
        }
        <cmd:ResourceProxy id="{ $corpus?name }-api-metadata">
          <cmd:ResourceType
            mimetype="application/json"
          >Resource</cmd:ResourceType>
          <cmd:ResourceRef>{ $links?api-metadata }</cmd:ResourceRef>
        </cmd:ResourceProxy>
        {
          if ($links?repository) then
            <cmd:ResourceProxy id="{ $corpus?name }-repository">
              <cmd:ResourceType mimetype="text/html">Resource</cmd:ResourceType>
              <cmd:ResourceRef>{ $links?repository }</cmd:ResourceRef>
            </cmd:ResourceProxy>
          else (
          )
        }
      </cmd:ResourceProxyList>
      <cmd:JournalFileProxyList />
      <cmd:ResourceRelationList />
    </cmd:Resources>
    <cmd:Components>
      <cmdp:collection>
        <cmdp:CollectionInfo>
          <cmdp:Name>{ $corpus?acronym }</cmdp:Name>
          <cmdp:Title>{ $corpus?title }</cmdp:Title>
          <cmdp:Owner>DraCor</cmdp:Owner>
          {
            for $code in $corpus?languages
            return <cmdp:ISO639>
              <cmdp:iso-639-3-code>{ $code }</cmdp:iso-639-3-code>
            </cmdp:ISO639>
          }
          <cmdp:Modality><cmdp:Modality>Written</cmdp:Modality></cmdp:Modality>
          {
            if ($corpus?description) then
              <cmdp:Description>
                <cmdp:Description>
                  { dpmh:plain-text($corpus?description) }
                </cmdp:Description>
              </cmdp:Description>
            else (
            )
          }
        </cmdp:CollectionInfo>
        <cmdp:License>
          {
            if ($corpus?licence and $corpus?licenceUrl) then (
              <cmdp:DistributionType>public</cmdp:DistributionType>,
              <cmdp:LicenseName>{ $corpus?licence }</cmdp:LicenseName>,
              <cmdp:LicenseURL>{ $corpus?licenceUrl }</cmdp:LicenseURL>
            ) else (
              <cmdp:DistributionType>unspecified</cmdp:DistributionType>,
              <cmdp:LicenseName>
                { ($corpus?licence, "unspecified, see repository")[1] }
              </cmdp:LicenseName>,
              <cmdp:LicenseURL>
                {
                  (
                    $corpus?licenceUrl, $links?repository, $links?landing-page
                  )[1]
                }
              </cmdp:LicenseURL>
            )
          }
        </cmdp:License>
        <cmdp:Contact>
          <cmdp:Email>{ $dpmh:admin-email }</cmdp:Email>
          <cmdp:Organisation>DraCor</cmdp:Organisation>
          <cmdp:Website>https://dracor.org</cmdp:Website>
        </cmdp:Contact>
        <cmdp:WebReference>
          <cmdp:Website>{ $links?landing-page }</cmdp:Website>
          <cmdp:Description>Corpus page on DraCor</cmdp:Description>
        </cmdp:WebReference>
        {
          if ($links?doi) then
            <cmdp:WebReference>
              <cmdp:Website>{ $links?doi }</cmdp:Website>
              <cmdp:Description>
                { "Archived versions on Zenodo (concept DOI)" }
              </cmdp:Description>
            </cmdp:WebReference>
          else (
          )
        }
        {
          if ($links?repository) then
            <cmdp:WebReference>
              <cmdp:Website>{ $links?repository }</cmdp:Website>
              <cmdp:Description>
                {
                  "Source repository" ||
                    (
                      if ($corpus?commit) then
                        " at commit " || $corpus?commit
                      else
                        ""
                    )
                }
              </cmdp:Description>
            </cmdp:WebReference>
          else (
          )
        }
        <cmdp:WebReference>
          <cmdp:Website>{ $links?api }</cmdp:Website>
          <cmdp:Description>DraCor API</cmdp:Description>
        </cmdp:WebReference>
        <cmdp:WebReference>
          <cmdp:Website>{ $links?dts }</cmdp:Website>
          <cmdp:Description>
            { "Distributed Text Services (DTS) collection" }
          </cmdp:Description>
        </cmdp:WebReference>
      </cmdp:collection>
    </cmd:Components>
  </cmd:CMD>
};

(:
 : --------------------
 : Verbs
 : --------------------
 :)

declare function dpmh:identify($args as map(*)) as element(oai:OAI-PMH) {
  let $datestamps := dpmh:corpora()!?datestamp
  let $earliest := (
    min($datestamps!xs:dateTime(.))!dpmh:utc(.), "1970-01-01T00:00:00Z"
  )[1]
  return dpmh:response(
    $args,
    <Identify xmlns="http://www.openarchives.org/OAI/2.0/">
      <repositoryName>{ $dpmh:repository-name }</repositoryName>
      <baseURL>{ $dpmh:base-url }</baseURL>
      <protocolVersion>2.0</protocolVersion>
      <adminEmail>{ $dpmh:admin-email }</adminEmail>
      <earliestDatestamp>{ $earliest }</earliestDatestamp>
      <deletedRecord>no</deletedRecord>
      <granularity>{ $dpmh:granularity }</granularity>
      {
        (: the oai-identifier scheme requires a domain name :)
        if (
          matches(
            $dpmh:repository-id,
            "^[a-zA-Z][a-zA-Z0-9\-]*(\.[a-zA-Z][a-zA-Z0-9\-]*)+$"
          )
        ) then
          <description>
            <oai-identifier
              xmlns="http://www.openarchives.org/OAI/2.0/oai-identifier"
              xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/oai-identifier http://www.openarchives.org/OAI/2.0/oai-identifier.xsd"
            >
              <scheme>oai</scheme>
              <repositoryIdentifier>
                { $dpmh:repository-id }
              </repositoryIdentifier>
              <delimiter>:</delimiter>
              <sampleIdentifier>{ $dpmh:id-prefix }ger</sampleIdentifier>
            </oai-identifier>
          </description>
        else (
        )
      }
    </Identify>
  )
};

declare function dpmh:list-metadata-formats(
  $args as map(*)
) as element(oai:OAI-PMH) {
  if ($args?identifier and empty(dpmh:corpus($args?identifier))) then
    dpmh:response(
      $args,
      dpmh:error("idDoesNotExist", "Unknown identifier: " || $args?identifier)
    )
  else
    dpmh:response(
      $args,
      <ListMetadataFormats xmlns="http://www.openarchives.org/OAI/2.0/">
        {
          for $prefix in ("oai_dc", "cmdi")
          return <metadataFormat>
            <metadataPrefix>{ $prefix }</metadataPrefix>
            <schema>{ $dpmh:formats($prefix)?schema }</schema>
            <metadataNamespace>
              { $dpmh:formats($prefix)?namespace }
            </metadataNamespace>
          </metadataFormat>
        }
      </ListMetadataFormats>
    )
};

declare function dpmh:list-sets($args as map(*)) as element(oai:OAI-PMH) {
  if ($args?resumptionToken) then
    dpmh:response(
      $args,
      dpmh:error("badResumptionToken", "Invalid resumption token")
    )
  else
    dpmh:response(
      $args,
      dpmh:error("noSetHierarchy", "This repository does not support sets")
    )
};

(:~
 : ListIdentifiers and ListRecords
 :)
declare function dpmh:list(
  $verb as xs:string,
  $args as map(*)
) as element(oai:OAI-PMH) {
  let $from := $args?from!dpmh:parse-date(., false())
  let $until := $args?until!dpmh:parse-date(., true())
  return if ($args?resumptionToken) then
    if (map:size($args) gt 2) then
      dpmh:response(
        map {},
        dpmh:error("badArgument", "resumptionToken is an exclusive argument")
      )
    else
      dpmh:response(
        $args,
        dpmh:error("badResumptionToken", "Invalid resumption token")
      )
  else if (empty($args?metadataPrefix)) then
    dpmh:response(
      map {},
      dpmh:error("badArgument", "Missing argument: metadataPrefix")
    )
  else if ($args?from and empty($from)) then
    dpmh:response(map {}, dpmh:error("badArgument", "Invalid date: from"))
  else if ($args?until and empty($until)) then
    dpmh:response(map {}, dpmh:error("badArgument", "Invalid date: until"))
  else if (
    exists($from) and exists($until) and $from?granularity ne $until?granularity
  ) then
    dpmh:response(
      map {},
      dpmh:error("badArgument", "from and until must have the same granularity")
    )
  else if (
    exists($from) and exists($until) and $from?value gt $until?value
  ) then
    dpmh:response(
      map {},
      dpmh:error("badArgument", "from must not be later than until")
    )
  else if (not(map:contains($dpmh:formats, $args?metadataPrefix))) then
    dpmh:response(
      $args,
      dpmh:error(
        "cannotDisseminateFormat",
        "Unsupported metadata format: " || $args?metadataPrefix
      )
    )
  else if ($args?set) then
    dpmh:response(
      $args,
      dpmh:error("noSetHierarchy", "This repository does not support sets")
    )
  else
    let $corpora := dpmh:corpora()[(
      empty($from) or xs:dateTime(?datestamp) ge $from?value
    ) and
      (empty($until) or xs:dateTime(?datestamp) le $until?value)]
    return if (empty($corpora)) then
      dpmh:response(
        $args,
        dpmh:error("noRecordsMatch", "No records match the request")
      )
    else if ($verb = "ListIdentifiers") then
      dpmh:response(
        $args,
        <ListIdentifiers xmlns="http://www.openarchives.org/OAI/2.0/">
          { $corpora!dpmh:header(.) }
        </ListIdentifiers>
      )
    else
      dpmh:response(
        $args,
        <ListRecords xmlns="http://www.openarchives.org/OAI/2.0/">
          { $corpora!dpmh:record(., $args?metadataPrefix) }
        </ListRecords>
      )
};

declare function dpmh:get-record($args as map(*)) as element(oai:OAI-PMH) {
  if (empty($args?identifier) or empty($args?metadataPrefix)) then
    dpmh:response(
      map {},
      dpmh:error(
        "badArgument",
        "GetRecord requires the arguments identifier and metadataPrefix"
      )
    )
  else
    let $corpus := dpmh:corpus($args?identifier)
    return if (empty($corpus)) then
      dpmh:response(
        $args,
        dpmh:error("idDoesNotExist", "Unknown identifier: " || $args?identifier)
      )
    else if (not(map:contains($dpmh:formats, $args?metadataPrefix))) then
      dpmh:response(
        $args,
        dpmh:error(
          "cannotDisseminateFormat",
          "Unsupported metadata format: " || $args?metadataPrefix
        )
      )
    else
      dpmh:response(
        $args,
        <GetRecord xmlns="http://www.openarchives.org/OAI/2.0/">
          { dpmh:record($corpus, $args?metadataPrefix) }
        </GetRecord>
      )
};

(:~
 : Find a corpus by its OAI identifier
 :)
declare function dpmh:corpus($identifier as xs:string) as map(*)? {
  if (starts-with($identifier, $dpmh:id-prefix)) then
    dpmh:corpora()[?identifier = $identifier]
  else (
  )
};

(:~
 : Validate the arguments and dispatch the request to the verb.
 :)
declare function dpmh:handle(
  $verb as xs:string*,
  $identifier as xs:string*,
  $metadata-prefix as xs:string*,
  $from as xs:string*,
  $until as xs:string*,
  $set as xs:string*,
  $resumption-token as xs:string*
) as element(oai:OAI-PMH) {
  let $given := map {
    "identifier": $identifier,
    "metadataPrefix": $metadata-prefix,
    "from": $from,
    "until": $until,
    "set": $set,
    "resumptionToken": $resumption-token
  }
  let $repeated := (
    if (count($verb) gt 1) then
      "verb"
    else (
    ),
    map:keys($given)[count($given(.)) gt 1]
  )
  return if (empty($verb) or not(map:contains($dpmh:verbs, $verb[1]))) then
    dpmh:response(
      map {},
      dpmh:error(
        "badVerb",
        if (empty($verb)) then
          "Missing verb argument"
        else
          "Illegal verb: " || $verb[1]
      )
    )
  else if (exists($repeated)) then
    dpmh:response(
      map {},
      dpmh:error(
        "badArgument",
        "Repeated argument: " || string-join($repeated, ", ")
      )
    )
  else
    let $args := map:merge(
      (
        map:entry("verb", $verb),
        for $key in map:keys($given)
        where exists($given($key))
        return map:entry($key, $given($key))
      )
    )
    let $illegal := map:keys($args)[not(. = ("verb", $dpmh:verbs($verb)))]
    return if (exists($illegal)) then
      dpmh:response(
        map {},
        dpmh:error(
          "badArgument",
          "Illegal argument for " ||
            $verb ||
            ": " ||
            string-join($illegal, ", ")
        )
      )
    else
      switch ($verb)
        case "Identify" return
          dpmh:identify($args)
        case "ListMetadataFormats" return
          dpmh:list-metadata-formats($args)
        case "ListSets" return
          dpmh:list-sets($args)
        case "GetRecord" return
          dpmh:get-record($args)
        default return
          dpmh:list($verb, $args)
};

(:
 : --------------------
 : Endpoints
 : --------------------
 :)

(:~
 : OAI-PMH endpoint (GET)
 :)
declare
  %rest:GET
  %rest:path("/v1/oai")
  %rest:query-param("verb", "{$verb}")
  %rest:query-param("identifier", "{$identifier}")
  %rest:query-param("metadataPrefix", "{$metadata-prefix}")
  %rest:query-param("from", "{$from}")
  %rest:query-param("until", "{$until}")
  %rest:query-param("set", "{$set}")
  %rest:query-param("resumptionToken", "{$resumption-token}")
  %output:method("xml")
  %output:media-type("text/xml")
function dpmh:oai-get(
  $verb as xs:string*,
  $identifier as xs:string*,
  $metadata-prefix as xs:string*,
  $from as xs:string*,
  $until as xs:string*,
  $set as xs:string*,
  $resumption-token as xs:string*
) {
  dpmh:handle(
    $verb,
    $identifier,
    $metadata-prefix,
    $from,
    $until,
    $set,
    $resumption-token
  )
};

(:~
 : OAI-PMH endpoint (POST with application/x-www-form-urlencoded body)
 :)
declare
  %rest:POST
  %rest:path("/v1/oai")
  %rest:form-param("verb", "{$verb}")
  %rest:form-param("identifier", "{$identifier}")
  %rest:form-param("metadataPrefix", "{$metadata-prefix}")
  %rest:form-param("from", "{$from}")
  %rest:form-param("until", "{$until}")
  %rest:form-param("set", "{$set}")
  %rest:form-param("resumptionToken", "{$resumption-token}")
  %output:method("xml")
  %output:media-type("text/xml")
function dpmh:oai-post(
  $verb as xs:string*,
  $identifier as xs:string*,
  $metadata-prefix as xs:string*,
  $from as xs:string*,
  $until as xs:string*,
  $set as xs:string*,
  $resumption-token as xs:string*
) {
  dpmh:handle(
    $verb,
    $identifier,
    $metadata-prefix,
    $from,
    $until,
    $set,
    $resumption-token
  )
};
