# url formats
# http://catalog.hathitrust.org/api/volumes/brief/<id type>/<id value>.json
# http://catalog.hathitrust.org/api/volumes/full/<id type>/<id value>.json

# url1 <- 'http://catalog.hathitrust.org/api/volumes/brief/oclc/424023.json'
# url2 <- 'http://catalog.hathitrust.org/api/volumes/full/oclc/424023.json'
# res <- GET(url2)
# stop_for_status(res)
# tt <- content(res, "text")
# jsonlite::fromJSON(tt)

#' HathiTrust bibliographic API
#'
#' @export
#' @param oclc OCLC Number. Will be normalized to just digits.
#' @param lccn Will be normalized as recommended
#' @param issn Will be normalized to just digits
#' @param isbn Will be normalized to just digits (and possible trailing X). ISBN-13s will be left
#'  alone; ISBN-10s will search against both the ISBN-10 and the ISBN-13
#' @param htid The HathiTrust Volume ID of a particular volume (e.g., mdp.39015058510069)
#' @param recordnumber The 9-digit HathiTrust record number, as described above.
#' @param ids A list of length 1 or more, with lists or vectors inside with many ids
#' to search for
#' @param which (character) One of brief or full.
#' @param searchfor (character) One of single or many.
#' @param ... Further args passed on to [crul::HttpClient], see examples
#'
#' @author Scott Chamberlain <myrmecocystus@@gmail.com>
#' 
#' @return 
#' 
#' There are two sections: Records which holds basic metadata about the set of records which match 
#' the query, and Items which lists the complete set of individual HathiTrust items (volumes) 
#' associated with those records.
#' 
#' **Records**
#' 
#' The records section. The records structure is a hash keyed on the nine-digit record number of 
#' each matched record. It may easily contain multiple records, since duplicates, while not 
#' common, are certainly possible.
#' 
#' For each record:
#' 
#' - recordURL: The URL to the catalog display record.
#' - titles: The list of titles associated with this record, for sanity checking. This list 
#'  includes the standard (MARC field 245) title with and without leading articles, and any 
#'  vernacular (foreign language) titles provided in the record (MARC field 880).
#' - isbns, issns, lccns, oclcs, lccns: Each is a (possibly empty) list of identifiers of the 
#'  appropriate type.
#' - marc-xml: The full MARC-XML of the record if the URL was of the form /api/volumes/full/...
#'  MARC-XML is not included in brief return values.
#' 
#' **Items**
#' 
#' The items structure is an array of hashes describing all the available items associated with 
#' matched records. There may be multiple items because the record(s) in question describe a 
#' serial or multi-volume set, or because identical volumes were digitized at more than one 
#' contributing institution.
#' 
#' For each item:
#' 
#' - orig: The originating institution -- where this particular volume was digitized.
#' - fromRecord: The nine-digit record number to which this particular item is attached. It 
#'  will always be one of the records listed in the records section.
#' - htid: The HathiTrust volume id.
#' - itemURL: The URL to this item in the pageturner interface. This is trivially derived from 
#'  the htid at the moment, but is included here in the event that the handle URLs get more complex 
#'  in the future.
#' - rightsCode: The rights code as used in the downloadable files, describing the copyright 
#'  status of the item and what users in various locales are able to do with it.
#' - lastUpdate: The date (YYYYMMDD) this item was ingested or last changed (because, e.g., 
#'  the rights determination changed).
#' - enumcron: The enumeration/chronology of the item, describing its place in a series. 
#'  These are commonly of the form, "vol. 3, n. 2 1993" or something similar. Used to sort the 
#'  items when present.
#' - usRightsString: A textual description of the rights for a US-based user. This is, again, 
#'  trivially derived from the rightsCode, but useful enough to the majority of likely users that 
#'  it is included here. Will be either "Limited (search only)" or "Full View." As noted, a 
#'  reasonably-sophisticated attempt is made to sort items by their enumcron (when present), 
#'  often resulting in the items listed correctly by volume/number. Variation in the way these 
#'  data have been entered at different institutions and at different times makes it impractical 
#'  to guarantee the order will be correct, but it is more often than not correct.
#' 
#' @references <http://www.hathitrust.org/bib_api>
#'
#' @examples \dontrun{
#' # Search for a sinlge item by single identifier
#' hathi_bib(oclc=424023)
#' hathi_bib(oclc=424023, which='full')
#' hathi_bib(htid='mdp.39015058510069')
#' hathi_bib(lccn='21019671')
#' hathi_bib(recordnumber='009585561')
#' hathi_bib(issn='9781149102480')
#'
#' # Search for a single item by many identifiers
#' hathi_bib(htid='BJD1', oclc=424023, isbn='0030110408')
#' hathi_bib(htid='BJD1', oclc=424023, isbn='0030110408', which='full')
#'
#' # Search for many items by a single identifier each
#' hathi_bib(lccn='70628581', isbn='0030110408', searchfor='many')
#'
#' # Search for many items by many identifiers each
#' hathi_bib(ids=list(list(htid='BJD1', oclc=424023, isbn='0030110408'),
#'                    list(lccn='70628581', isbn='0030110408')), searchfor='many')
#'
#' # Curl debugging
#' hathi_bib(oclc=424023, verbose = TRUE)
#' }

hathi_bib <- function(oclc=NULL, lccn=NULL, issn=NULL, isbn=NULL, htid=NULL, recordnumber=NULL,
  ids=list(), which='brief', searchfor='single', ...)
{
  which <- match.arg(which, c('brief','full'))

  if(length(ids) == 0){
    calls <- names(sapply(match.call(), deparse))[-1]
    c_vec <- calls[calls %in% c('oclc','lccn','issn','isbn','htid','recordnumber')]

    if(length(c_vec) == 0) stop('please provide at least 1 identifier')
    if(length(c_vec) == 1){
      url <- sprintf('http://catalog.hathitrust.org/api/volumes/%s/%s/%s.json', which, c_vec, get(c_vec))
    }
    if(length(c_vec) > 1){
      searchfor <- match.arg(searchfor, c('single','many'))
      args <- switch(searchfor,
                     single = makeargs(c_vec),
                     many = makeargs(c_vec, sep = "|"))
      url <- sprintf('http://catalog.hathitrust.org/api/volumes/%s/json/%s', which, args)
    }
  } else {
    args <- paste0(vapply(ids, makeargsfromids, character(1)), collapse = "|")
    url <- sprintf('http://catalog.hathitrust.org/api/volumes/%s/json/%s', which, args)
  }

  cli <- crul::HttpClient$new(url, opts = list(...))
  res <- cli$get()
  res$raise_for_status()
  jsonlite::fromJSON(res$parse("UTF-8"))
}

makeargs <- function(x, sep=';'){
  out <- list()
  for(i in seq_along(x)){
    out[[i]] <- sprintf("%s:%s", x[[i]], get(x[[i]], envir = parent.frame()))
  }
  out2 <- paste(out, collapse = sep)
  gsub('htid', 'id', out2)
}

makeargsfromids <- function(x){
  out <- list()
  for(i in seq_along(x)){
    out[[i]] <- sprintf("%s:%s", names(x[i]), x[[i]])
  }
  out2 <- paste(out, collapse = ';')
  gsub('htid', 'id', out2)
}
