{
	"translatorID": "ca65189f-8815-4afe-8c8b-8c7c15f0edca",
	"label": "Better BibTeX",
	"creator": "Simon Kornblith, Richard Karnesky and Emiliano heyns",
	"target": "bib",
	"minVersion": "2.1.9",
	"maxVersion": "",
	"priority": 199,
  "configOptions": {
    "getCollections": "true"
  },
	"displayOptions": {
		"exportNotes": true,
		"exportFileData": false,
		"useJournalAbbreviation": false
	},
	"inRepository": true,
	"translatorType": 3,
	"browserSupport": "gcsv",
	"lastUpdated": "/*= timestamp =*/"
}

/*= include common.js =*/

var fieldMap = Dict({
  address:      {literal: 'place'},
  chapter:      {literal: 'section'},
  edition:      {literal: 'edition'},
  type:         'type',
  series:       {literal: 'series'},
  title:        {literal: 'title'},
  volume:       {literal: 'volume'},
  copyright:    {literal: 'rights'},
  isbn:         'ISBN',
  issn:         'ISSN',
  lccn:         'callNumber',
  shorttitle:   {literal: 'shortTitle'},
  url:          'url',
  doi:          'DOI',
  abstract:     'abstractNote',
  nationality:  'country',
  language:     'language',
  assignee:     'assignee'
});
var inputFieldMap = Dict({
  booktitle:    'publicationTitle',
  school:       'publisher',
  institution:  'publisher',
  publisher:    'publisher',
  issue:        'issue',
  location:     'place'
});

Translator.typeMap.toBibTeX = Dict({
  book:             ['book', 'booklet', 'manual', 'proceedings'],
  bookSection:      ['incollection', 'inbook'],
  journalArticle:   [':article', ':misc'],
  magazineArticle:  'article',
  newspaperArticle: 'article',
  thesis:           ['phdthesis', 'mastersthesis'],
  manuscript:       'unpublished',
  patent:           'patent',
  conferencePaper:  ['inproceedings', 'conference'],
  report:           'techreport',
  letter:           'misc',
  interview:        'misc',
  film:             'misc',
  artwork:          'misc',
  webpage:          'misc'
});

/*
 * three-letter month abbreviations. I assume these are the same ones that the
 * docs say are defined in some appendix of the LaTeX book. (i don't have the
 * LaTeX book.)
*/
var months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

function doExport() {
  //Zotero.write('% BibTeX export generated by Zotero '+Zotero.Utilities.getVersion());
  // to make sure the BOM gets ignored
  Zotero.write("\n");

  var first = true;
  while (item = Translator.nextItem()) {
    // determine type
    var type = getBibTeXType(item);

    if (!first) { Zotero.write(",\n\n"); }
    first = false;

    Zotero.write("\n\n");
    Zotero.write('@'+type+'{'+item.__citekey__);

    writeFieldMap(item, fieldMap);

    if (item.reportNumber || item.issue || item.seriesNumber || item.patentNumber) {
      writeField('number', latex_escape(item.reportNumber || item.issue || item.seriesNumber|| item.patentNumber));
    }

    if (item.accessDate){
      var accessYMD = item.accessDate.replace(/\s*\d+:\d+:\d+/, '');
      writeField('urldate', latex_escape(accessYMD));
    }

    if (item.publicationTitle) {
      if (item.itemType == 'bookSection' || item.itemType == 'conferencePaper') {
        writeField('booktitle', latex_escape(item.publicationTitle, {brace: true}));

      } else if (item.itemType == 'bookSection' || item.itemType == 'conferencePaper') {
        writeField('booktitle', latex_escape(item.publicationTitle, {brace: true}));

      } else {
        var abbr = Translator.useJournalAbbreviation && Zotero.BetterBibTeX.keymanager.journalAbbrev(item);
        if (abbr) {
          writeField('journal', latex_escape(abbr, {brace: true}));
        } else {
          writeField('journal', latex_escape(item.publicationTitle, {brace: true}));
        }
      }
    }

    if (item.publisher) {
      if (item.itemType == 'thesis') {
        writeField('school', latex_escape(item.publisher, {brace: true}));
      } else if (item.itemType =='report') {
        writeField('institution', latex_escape(item.publisher, {brace: true}));
      } else {
        writeField('publisher', latex_escape(item.publisher, {brace: true}));
      }
    }

    if (item.creators && item.creators.length) {
      // split creators into subcategories
      var authors = [];
      var editors = [];
      var translators = [];
      var collaborators = [];
      var primaryCreatorType = Zotero.Utilities.getCreatorsForType(item.itemType)[0];
      var creator;

      item.creators.forEach(function(creator) {
        if (('' + creator.firstName).trim() != '' && ('' + creator.lastName).trim() != '') {
          creatorString = creator.lastName + ', ' + creator.firstName;
        } else {
          creatorString = {literal: creator.lastName}
        }

        switch (creator.creatorType) {
          case 'editor':
          case 'seriesEditor':
            editors.push(creatorString);
            break;
          case 'translator':
            translators.push(creatorString);
          case primaryCreatorType:
            authors.push(creatorString);
            break;
          default:
            collaborators.push(creatorString);
        }
      });

      writeField('author', latex_escape(authors, {sep: ' and '}));
      writeField('editor', latex_escape(editors, {sep: ' and '}));
      writeField('translator', latex_escape(translators, {sep: ' and '}));
      writeField('collaborator', latex_escape(collaborators, {sep: ' and '}));
    }

    if (item.date) {
      var date = Zotero.Utilities.strToDate(item.date);
      if (typeof date.year === 'undefined') {
        writeField('year', latex_escape({literal:item.date}));
      } else {
        // need to use non-localized abbreviation
        if (typeof date.month == 'number') {
          writeField('month', latex_escape(months[date.month]), true); // no braces at all around the month
        }
        writeField('year', latex_escape(date.year));
      }
    }

    writeExtra(item, 'note');

    writeTags('keywords', item);

    writeField('pages', latex_escape(item.pages));

    // Commented out, because we don't want a books number of pages in the BibTeX "pages" field for books.
    //if (item.numPages) {
    //  writeField('pages', latex_escape(item.numPages));
    //}

    /* We'll prefer url over howpublished see
    https://forums.zotero.org/discussion/24554/bibtex-doubled-url/#Comment_157802

    if (item.itemType == 'webpage') {
      writeField('howpublished', item.url);
    }*/
    if (item.notes && Translator.exportNotes) {
      item.notes.forEach(function(note) {
        writeField('annote', latex_escape(Zotero.Utilities.unescapeHTML(note.note)));
      });
    }

    writeAttachments(item);

    flushEntry(item);

    Zotero.write("\n}");
  }

  exportJabRefGroups();

  Zotero.write("\n");
}

function addToExtra(item, str) {
  if (item.extra && item.extra != '') {
    item.extra += " \n" + str;
  } else {
    item.extra = str;
  }
}

function addToExtraData(data, key, value) {
  data.push(key.replace(/[=;]/g, '#') + '=' + value.replace(/[\r\n]+/g, ' ').replace(/[=;]g/, '#'));
}

function createZoteroReference(bibtexitem) {
  var type = Zotero.Utilities.trimInternal(bibtexitem.__type__.toLowerCase());
  if (bibtexitem.type) { type = Zotero.Utilities.trimInternal(bibtexitem.type.toLowerCase()); }
  type = Translator.typeMap.toZotero[type] || 'journalArticle';

  trLog('creating reference for ' + JSON.stringify(bibtexitem));

  var item = new Zotero.Item(type);
  item.itemID = bibtexitem.__key__;

  if (bibtexitem.__note__) {
    item.notes.push({note: ('The following fields were not imported:<br/>' + bibtexitem.__note__).trim(), tags: ['#BBT Import']});
  }

  var biblatexdata = [];
  Dict.forEach(bibtexitem, function(field, value) {

    if (['__note__', '__key__', '__type__', 'type', 'added-at', 'timestamp'].indexOf(field) >= 0) { return; }
    if (!value) { return; }
    if (typeof value == 'string') { value = Zotero.Utilities.trim(value); }
    if (value == '') { return; }

    if (fieldMap[field]) {
      zField = fieldMap[field];
      if (zField.literal) { zField = zField.literal; }
      item[zField] = value;

    } else if (inputFieldMap[field]) {
      zField = inputFieldMap[field];
      if (zField.literal) { zField = zField.literal; }
      item[zField] = value;

    } else if (field == 'journal') {
      if (item.publicationTitle) {
        item.journalAbbreviation = value;
      } else {
        item.publicationTitle = value;
      }

    } else if (field == 'fjournal') {
      if (item.publicationTitle) {
        // move publicationTitle to abbreviation
        item.journalAbbreviation = item.publicationTitle;
      }
      item.publicationTitle = value;

    } else if (field == 'author' || field == 'editor' || field == 'translator') {
      value.forEach(function(creator) {
        if (!creator) { return; }

        if (typeof creator == 'string') {
          creator = Zotero.Utilities.cleanAuthor(creator, field, false);
        } else {
          creator.creatorType = field;
        }

        item.creators.push(creator);
      });

    } else if (field == 'institution' || field == 'organization') {
      item.backupPublisher = value;

    } else if (field == 'number'){ // fix for techreport
      if (item.itemType == 'report') {
        item.reportNumber = value;
      } else if (item.itemType == 'book' || item.itemType == 'bookSection') {
        item.seriesNumber = value;
      } else if (item.itemType == 'patent'){
        item.patentNumber = value;
      } else {
        item.issue = value;
      }

    } else if (field == 'month') {
      var monthIndex = months.indexOf(value.toLowerCase());
      if (monthIndex >= 0) {
        value = Zotero.Utilities.formatDate({month:monthIndex});
      } else {
        value += ' ';
      }
    
      if (item.date) {
        if (value.indexOf(item.date) >= 0) {
          // value contains year and more
          item.date = value;
        } else {
          item.date = value+item.date;
        }
      } else {
        item.date = value;
      }

    } else if (field == 'year') {
      if (item.date) {
        if (item.date.indexOf(value) < 0) {
          // date does not already contain year
          item.date += value;
        }
      } else {
        item.date = value;
      }

    } else if (field == 'date') {
      //We're going to assume that 'date' and the date parts don't occur together. If they do, we pick date, which should hold all.
      item.date = value;

    } else if (field == 'pages') {
      if (item.itemType == 'book' || item.itemType == 'thesis' || item.itemType == 'manuscript') {
        item.numPages = value;
      } else {
        item.pages = value.replace(/--/g, '-');
      }

    } else if (field == 'note') {
      addToExtra(item, value);

    } else if (field == 'howpublished') {
      if (/^(https?:\/\/|mailto:)/i.test(value)) {
        item.url = value;
      } else {
        addToExtraData(biblatexdata, field, value);
      }

    //accept lastchecked or urldate for access date. These should never both occur. 
    //If they do we don't know which is better so we might as well just take the second one
    } else if (field == 'lastchecked'|| field == 'urldate'){
      item.accessDate = value;

    } else if (field == 'keywords' || field == 'keyword') {
      var kw = value.split(/[,;]/);
      if (kw.length == 1) {
        kw = value.split(/\s+/);
      }
      item.tags = kw.map(function(k) {
        return k.replace(/^[\s{]+|[}\s]+$/gm, '').trim();
      });

    } else if (field == 'comment' || field == 'annote' || field == 'review' || field == 'notes') {
      item.notes.push({note:Zotero.Utilities.text2html(value)});

    } else if (field == 'file') {
      value.forEach(function(attachment) {
        item.attachments.push(attachment);
      });

    } else {
      addToExtraData(biblatexdata, field, value);

    }
  });

  if (item.itemType == 'conferencePaper' && item.publicationTitle && !item.proceedingsTitle) {
    item.proceedingsTitle = item.publicationTitle;
    delete item.publicationTitle;
  }

  addToExtra(item, 'bibtex: ' + item.itemID);

  if (biblatexdata.length > 0) {
    biblatexdata.sort();
    addToExtra(item, "biblatexdata[" + biblatexdata.join(';') + ']');
  }

  if (!item.publisher && item.backupPublisher){
    item.publisher=item.backupPublisher;
    delete item.backupPublisher;
  }
  item.complete();
}

/*= include import.js =*/
