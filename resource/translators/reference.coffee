###
# h1 Global object: Translator
#
# The global Translator object allows access to the current configuration of the translator
#
# @param {enum} titleCase whether titles should be title-cased
# @param {boolean} fancyURLs set to true when BBT will generate \url{..} around the urls
###

###
# h1 class: Reference
#
# The Bib(La)TeX references are generated by the `Reference` class. Before being comitted to the cache, you can add
# postscript code that can manipulated the `fields` or the `referencetype`
#
# @param {Array} @fields Array of reference fields
# @param {String} @referencetype referencetype
# @param {Object} @item the current Zotero item being converted
###

###
# The fields are objects with the following keys:
#   * name: name of the Bib(La)TeX field
#   * value: the value of the field
#   * bibtex: the LaTeX-encoded value of the field
#   * enc: the encoding to use for the field
###
class Reference
  constructor: (@item) ->
    @fields = []
    @has = Object.create(null)
    @raw = (Translator.rawLaTag in @item.tags)

    if !@item.language
      @english = true
    else
      langlc = @item.language.toLowerCase()
      @language = Language.babelMap[langlc.replace(/[^a-z0-9]/, '_')]
      @language ||= Language.babelMap[langlc.replace(/-[a-z]+$/i, '').replace(/[^a-z0-9]/, '_')]
      if @language
        @language = @language[0]
      else
        sim = Language.lookup(langlc)
        if sim[0].sim >= 0.9
          @language = sim[0].lang
        else
          delete @language

      @english = @language in ['american', 'british', 'canadian', 'english', 'australian', 'newzealand', 'USenglish', 'UKenglish']

    @referencetype = Translator.typeMap.Zotero2BibTeX[@item.itemType] || 'misc'

    @override = Translator.extractFields(@item)

    for own attr, f of Translator.fieldMap || {}
      @add(@clone(f, @item[attr])) if f.name

    @add({name: 'timestamp', value: Translator.testing_timestamp || @item.dateModified || @item.dateAdded})

  ###
  # Return a copy of the given `field` with a new value
  #
  # @param {field} field to be cloned
  # @param {value} value to be assigned
  # @return {Object} copy of field settings with new value
  ###
  clone: (f, value) ->
    clone = JSON.parse(JSON.stringify(f))
    delete clone.bibtex
    clone.value = value
    return clone

  ###
  # 'Encode' to raw LaTeX value
  #
  # @param {field} field to encode
  # @return {String} unmodified `field.value`
  ###
  enc_raw: (f) ->
    return f.value

  ###
  # Encode to date
  #
  # @param {field} field to encode
  # @return {String} unmodified `field.value`
  ###
  isodate: (v, suffix = '') ->
    year = v["year#{suffix}"]
    return null unless year

    month = v["month#{suffix}"]
    month = "0#{month}".slice(-2) if month
    day = v["day#{suffix}"]
    day = "0#{day}".slice(-2) if day

    date = '' + year
    if month
      date += "-#{month}"
      date += "-#{day}" if day
    return date

  enc_date: (f) ->
    return null unless f.value

    value = f.value
    value = Zotero.BetterBibTeX.parseDateToObject(value, @item.language) if typeof f.value == 'string'

    if value.literal
      return '\\bibstring{nodate}' if value.literal == 'n.d.'
      return @enc_latex(@clone(f, value.literal))

    date = @isodate(value)
    return null unless date

    enddate = @isodate(value, '_end')
    date += "/#{enddate}" if enddate

    return @enc_latex({value: date})

  ###
  # Encode to LaTeX url
  #
  # @param {field} field to encode
  # @return {String} field.value encoded as verbatim LaTeX string (minimal escaping). If preference `fancyURLs` is on, wraps return value in `\url{string}`
  ###
  enc_url: (f) ->
    value = @enc_verbatim(f)
    return "\\url{#{value}}" if Translator.fancyURLs
    return value

  ###
  # Encode to verbatim LaTeX
  #
  # @param {field} field to encode
  # @return {String} field.value encoded as verbatim LaTeX string (minimal escaping).
  ###
  enc_verbatim: (f) ->
    return @toVerbatim(f.value)

  nonLetters: new XRegExp("[^\\p{Letter}]", 'g')
  punctuationAtEnd: new XRegExp("[\\p{Punctuation}]$")
  startsWithLowercase: new XRegExp("^[\\p{Ll}]")
  _enc_creators_postfix_particle: (particle) ->
    # space at end is always OK
    return '' if particle[particle.length - 1] == ' '

    # if BBLT, always add a space if it isn't there
    return ' ' if Translator.BetterBibLaTeX

    # otherwise, we're in BBT.

    # If the particle ends in a period, add a space
    return ' ' if particle[particle.length - 1] == '.'

    # if it ends in any other punctuation, it's probably something like d'Medici -- no space
    return '' if XRegExp.test(particle, @punctuationAtEnd)

    # otherwise, add a space
    return ' '

  _enc_creators_quote_separators: (value) ->
    return ((if i % 2 == 0 then n else new String(n)) for n, i in value.split(/(\s+and\s+|,)/i))

  _enc_creators_biblatex: (name) ->
    for particle in ['non-dropping-particle', 'dropping-particle']
      name[particle] += @_enc_creators_postfix_particle(name[particle]) if name[particle]

    for k, v of name
      continue unless typeof v == 'string'
      switch
        when v.length > 1 && v[0] == '"' && v[v.length - 1] == '"'
          name[k] = @enc_latex({ value: new String(v.slice(1, -1)) })
        when k == 'family' && XRegExp.test(v, @startsWithLowercase)
          name[k] = @enc_latex({ value: new String(v) })
        else
          name[k] = @enc_latex({ value: @_enc_creators_quote_separators(v), sep: ' '})

    latex = ''
    latex += name['dropping-particle'] if name['dropping-particle']
    latex += name['non-dropping-particle'] if name['non-dropping-particle']
    latex += name.family if name.family
    latex += ", #{name.suffix}" if name.suffix
    latex += ", #{name.given || ''}"

    return latex

  _enc_creators_bibtex: (name) ->
    for particle in ['non-dropping-particle', 'dropping-particle']
      name[particle] += @_enc_creators_postfix_particle(name[particle]) if name[particle]

    if name.family.length > 1 && name.family[0] == '"' && name.family[name.family.length - 1] == '"'
      name.family = name.family.slice(1, -1)

    latex = [new String((part for part in [name['dropping-particle'], name['non-dropping-particle'], name.family] when part).join(''))]
    latex.push(name.suffix) if name.suffix
    latex.push(name.given) if name.given
    return @enc_latex({value: latex, sep: ', '})

  ###
  # Encode creators to author-style field
  #
  # @param {field} field to encode. The 'value' must be an array of Zotero-serialized `creator` objects.
  # @return {String} field.value encoded as author-style value
  ###
  enc_creators: (f, raw) ->
    return null if f.value.length == 0

    encoded = []
    for creator in f.value
      switch
        when creator.name || (creator.lastName && creator.fieldMode == 1)
          name = if raw then "{#{creator.name || creator.lastName}}" else @enc_latex({value: new String(creator.name || creator.lastName)})

        when raw
          name = [creator.lastName || '', creator.firstName || ''].join(', ')

        when creator.lastName || creator.firstName
          name = {family: creator.lastName || '', given: creator.firstName || ''}

          Zotero.BetterBibTeX.CSL.parseParticles(name)

          @useprefix ||= !!name['non-dropping-particle']
          @juniorcomma ||= (f.juniorcomma && name['comma-suffix'])

          if Translator.BetterBibTeX
            name = @_enc_creators_bibtex(name)
          else
            name = @_enc_creators_biblatex(name)

        else
          continue

      encoded.push(name.trim())

    return encoded.join(' and ')

  ###
  # Encode text to LaTeX literal list (double-braced)
  #
  # This encoding supports simple HTML markup.
  #
  # @param {field} field to encode.
  # @return {String} field.value encoded as author-style value
  ###
  enc_literal: (f, raw) ->
    return @enc_latex({value: new String(f.value)}, raw)

  ###
  # Encode text to LaTeX
  #
  # This encoding supports simple HTML markup.
  #
  # @param {field} field to encode.
  # @return {String} field.value encoded as author-style value
  ###
  enc_latex: (f, raw) ->
    return f.value if typeof f.value == 'number'
    return null unless f.value

    if Array.isArray(f.value)
      return null if f.value.length == 0
      return (@enc_latex(@clone(f, word), raw) for word in f.value).join(f.sep || '')

    return f.value if raw

    value = LaTeX.text2latex(f.value, {autoCase: f.autoCase && @english})
    value = new String("{#{value}}") if f.value instanceof String
    return value

  enc_tags: (f) ->
    tags = (tag for tag in f.value || [] when tag && tag != Translator.rawLaTag)
    return null if tags.length == 0

    # sort tags for stable tests
    tags.sort() if Translator.testing

    tags = for tag in tags
      if Translator.BetterBibTeX
        tag = tag.replace(/([#\\%&])/g, '\\$1')
      else
        tag = tag.replace(/([#%\\])/g, '\\$1')

      # the , -> ; is unfortunate, but I see no other way
      tag = tag.replace(/,/g, ';')

      # verbatim fields require balanced braces -- please just don't use braces in your tags
      balanced = 0
      for ch in tag
        switch ch
          when '{' then balanced += 1
          when '}' then balanced -= 1
        break if balanced < 0
      tag = tag.replace(/{/g, '(').replace(/}/g, ')') if balanced != 0
      tag

    return tags.join(',')

  enc_attachments: (f) ->
    return null if not f.value || f.value.length == 0
    attachments = []
    errors = []

    for att in f.value
      a = {
        title: att.title
        path: att.localPath
        mimetype: att.mimeType || ''
      }

      save = Translator.exportFileData && att.defaultPath && att.saveFile
      a.path = att.defaultPath if save

      continue unless a.path # amazon/googlebooks etc links show up as atachments without a path

      a.title ||= att.path.replace(/.*[\\\/]/, '') || 'attachment'

      if a.path.match(/[{}]/) # latex really doesn't want you to do this.
        errors.push("BibTeX cannot handle file paths with braces: #{JSON.stringify(a.path)}")
        continue

      a.mimetype = 'application/pdf' if !a.mimetype && a.path.slice(-4).toLowerCase() == '.pdf'

      switch
        when save
          att.saveFile(a.path)
        when Translator.testing
          Translator.attachmentCounter += 1
          a.path = "files/#{Translator.attachmentCounter}/#{att.localPath.replace(/.*[\/\\]/, '')}"
        when Translator.exportPath && att.localPath.indexOf(Translator.exportPath) == 0
          a.path = att.localPath.slice(Translator.exportPath.length)

      attachments.push(a)

    f.errors = errors if errors.length != 0
    return null if attachments.length == 0

    # sort attachments for stable tests, and to make non-snapshots the default for JabRef to open (#355)
    attachments.sort((a, b) ->
      return 1  if a.mimetype == 'text/html' && b.mimetype != 'text/html'
      return -1 if b.mimetype == 'text/html' && a.mimetype != 'text/html'
      return a.path.localeCompare(b.path)
    )

    return (att.path.replace(/([\\{};])/g, "\\$1") for att in attachments).join(';') if Translator.attachmentsNoMetadata
    return ((part.replace(/([\\{}:;])/g, "\\$1") for part in [att.title, att.path, att.mimetype]).join(':') for att in attachments).join(';')

  isBibVarRE: /^[a-z][a-z0-9_]*$/i
  isBibVar: (value) ->
    return Translator.preserveBibTeXVariables && value && typeof value == 'string' && @isBibVarRE.test(value)
  ###
  # Add a field to the reference field set
  #
  # @param {field} field to add. 'name' must be set, and either 'value' or 'bibtex'. If you set 'bibtex', BBT will trust
  #   you and just use that as-is. If you set 'value', BBT will escape the value according the encoder passed in 'enc'; no
  #   'enc' means 'enc_latex'. If you pass both 'bibtex' and 'latex', 'bibtex' takes precedence (and 'value' will be
  #   ignored)
  ###
  add: (field) ->
    if ! field.bibtex
      return if typeof field.value != 'number' && not field.value
      return if typeof field.value == 'string' && field.value.trim() == ''
      return if Array.isArray(field.value) && field.value.length == 0

    @remove(field.name) if field.replace
    throw "duplicate field '#{field.name}' for #{@item.__citekey__}" if @has[field.name] && !field.allowDuplicates

    if ! field.bibtex
      Translator.debug('add:', {
        field
        preserve: Translator.preserveBibTeXVariables
        match: @isBibVar(field.value)
      })
      if typeof field.value == 'number' || (field.preserveBibTeXVariables && @isBibVar(field.value))
        value = field.value
      else
        enc = field.enc || Translator.fieldEncoding?[field.name] || 'latex'
        value = @["enc_#{enc}"](field, (if field.enc && field.enc != 'creators' then false else @raw))

        return unless value

        value = "{#{value}}" unless field.bare && !field.value.match(/\s/)

      field.bibtex = "#{value}"

    field.bibtex = field.bibtex.normalize('NFKC') if @normalize
    @fields.push(field)
    @has[field.name] = field

  ###
  # Remove a field from the reference field set
  #
  # @param {name} field to remove.
  # @return {Object} the removed field, if present
  ###
  remove: (name) ->
    return unless @has[name]
    removed = @has[name]
    delete @has[name]
    @fields = (field for field in @fields when field.name != name)
    return removed

  normalize: (typeof (''.normalize) == 'function')

  postscript: ->

  complete: ->
    if Translator.DOIandURL != 'both'
      if @has.doi && @has.url
        switch Translator.DOIandURL
          when 'doi' then @remove('url')
          when 'url' then @remove('doi')

    fields = []
    for own name, value of @override
      raw = (value.format in ['naive', 'json'])
      name = name.toLowerCase()

      # psuedo-var, sets the reference type
      if name == 'referencetype'
        @referencetype = value.value
        continue

      # these are handled just like 'arxiv' and 'lccn', respectively
      value.format = 'key-value' if name in ['pmid', 'pmcid']

      if value.format == 'csl'
        # CSL names are not in BibTeX format, so only add it if there's a mapping
        cslvar = Translator.CSLVariables[name]
        name = cslvar[(if Translator.BetterBibLaTeX then 'BibLaTeX' else 'BibTeX')]
        name = name.call(@) if typeof name == 'function'
        autoCase = name in ['title', 'shorttitle', 'origtitle', 'booktitle', 'maintitle']

        if name
          fields.push({ name, value: value.value, autoCase, enc: (if cslvar.type == 'creator' then 'creators' else cslvar.type), raw })

        else
          Translator.debug('Unmapped CSL field', name, '=', value.value)

      else
        switch name
          when 'mr'
            fields.push({ name: 'mrnumber', value: value.value, raw: raw })
          when 'zbl'
            fields.push({ name: 'zmnumber', value: value.value, raw: raw })
          when 'lccn', 'pmcid'
            fields.push({ name: name, value: value.value, raw: raw })
          when 'pmid', 'arxiv', 'jstor', 'hdl'
            if Translator.BetterBibLaTeX
              fields.push({ name: 'eprinttype', value: name.toLowerCase() })
              fields.push({ name: 'eprint', value: value.value, raw: raw })
            else
              fields.push({ name, value: value.value, raw: raw })
          when 'googlebooksid'
            if Translator.BetterBibLaTeX
              fields.push({ name: 'eprinttype', value: 'googlebooks' })
              fields.push({ name: 'eprint', value: value.value, raw: raw })
            else
              fields.push({ name: 'googlebooks', value: value.value, raw: raw })
          when 'xref'
            fields.push({ name, value: value.value, enc: 'raw' })

          else
            fields.push({ name, value: value.value, raw: raw })

    for name in Translator.skipFields
      @remove(name)

    for field in fields
      name = field.name.split('.')
      if name.length > 1
        continue unless @referencetype == name[0]
        field.name = name[1]

      if (typeof field.value == 'string') && field.value.trim() == ''
        @remove(field.name)
        continue

      field = @clone(Translator.BibLaTeXDataFieldMap[field.name], field.value) if Translator.BibLaTeXDataFieldMap[field.name]
      field.replace = true
      @add(field)

    @add({name: 'type', value: @referencetype}) if @fields.length == 0

    try
      @postscript()
    catch err
      Translator.debug('postscript error:', err.message)

    # sort fields for stable tests
    @fields.sort((a, b) -> ("#{a.name} = #{a.value}").localeCompare(("#{b.name} = #{b.value}"))) if Translator.testing

    ref = "@#{@referencetype}{#{@item.__citekey__},\n"
    ref += ("  #{field.name} = #{field.bibtex}" for field in @fields).join(',\n')
    ref += '\n}\n\n'
    Zotero.write(ref)

    Zotero.BetterBibTeX.cache.store(@item.itemID, Translator, @item.__citekey__, ref) if Translator.caching

  toVerbatim: (text) ->
    if Translator.BetterBibTeX
      value = ('' + text).replace(/([#\\%&{}])/g, '\\$1')
    else
      value = ('' + text).replace(/([\\{}])/g, '\\$1')
    value = value.replace(/[^\x21-\x7E]/g, ((chr) -> '\\%' + ('00' + chr.charCodeAt(0).toString(16).slice(-2)))) if not Translator.unicode
    return value

  hasCreator: (type) -> (@item.creators || []).some((creator) -> creator.creatorType == type)

Language = new class
  constructor: ->
    @babelMap = {
      af: 'afrikaans'
      am: 'amharic'
      ar: 'arabic'
      ast: 'asturian'
      bg: 'bulgarian'
      bn: 'bengali'
      bo: 'tibetan'
      br: 'breton'
      ca: 'catalan'
      cop: 'coptic'
      cy: 'welsh'
      cz: 'czech'
      da: 'danish'
      de_1996: 'ngerman'
      de_at_1996: 'naustrian'
      de_at: 'austrian'
      de_de_1996: 'ngerman'
      de: ['german', 'germanb']
      dsb: ['lsorbian', 'lowersorbian']
      dv: 'divehi'
      el: 'greek'
      el_polyton: 'polutonikogreek'
      en_au: 'australian'
      en_ca: 'canadian'
      en: 'english'
      en_gb: ['british', 'ukenglish']
      en_nz: 'newzealand'
      en_us: ['american', 'usenglish']
      eo: 'esperanto'
      es: 'spanish'
      et: 'estonian'
      eu: 'basque'
      fa: 'farsi'
      fi: 'finnish'
      fr_ca: [
        'acadian'
        'canadian'
        'canadien'
      ]
      fr: ['french', 'francais']
      fur: 'friulan'
      ga: 'irish'
      gd: ['scottish', 'gaelic']
      gl: 'galician'
      he: 'hebrew'
      hi: 'hindi'
      hr: 'croatian'
      hsb: ['usorbian', 'uppersorbian']
      hu: 'magyar'
      hy: 'armenian'
      ia: 'interlingua'
      id: [
        'indonesian'
        'bahasa'
        'bahasai'
        'indon'
        'meyalu'
      ]
      is: 'icelandic'
      it: 'italian'
      ja: 'japanese'
      kn: 'kannada'
      la: 'latin'
      lo: 'lao'
      lt: 'lithuanian'
      lv: 'latvian'
      ml: 'malayalam'
      mn: 'mongolian'
      mr: 'marathi'
      nb: ['norsk', 'bokmal']
      nl: 'dutch'
      nn: 'nynorsk'
      no: ['norwegian', 'norsk']
      oc: 'occitan'
      pl: 'polish'
      pms: 'piedmontese'
      pt_br: ['brazil', 'brazilian']
      pt: ['portuguese', 'portuges']
      pt_pt: 'portuguese'
      rm: 'romansh'
      ro: 'romanian'
      ru: 'russian'
      sa: 'sanskrit'
      se: 'samin'
      sk: 'slovak'
      sl: ['slovenian', 'slovene']
      sq_al: 'albanian'
      sr_cyrl: 'serbianc'
      sr_latn: 'serbian'
      sr: 'serbian'
      sv: 'swedish'
      syr: 'syriac'
      ta: 'tamil'
      te: 'telugu'
      th: ['thai', 'thaicjk']
      tk: 'turkmen'
      tr: 'turkish'
      uk: 'ukrainian'
      ur: 'urdu'
      vi: 'vietnamese'
      zh_latn: 'pinyin'
      zh: 'pinyin'
      zlm: [
        'malay'
        'bahasam'
        'melayu'
      ]
    }
    for own key, value of @babelMap
      @babelMap[key] = [value] if typeof value == 'string'

    # list of unique languages
    @babelList = []
    for own k, v of @babelMap
      for lang in v
        @babelList.push(lang) if @babelList.indexOf(lang) < 0

    @cache = Object.create(null)

#  @polyglossia = [
#    'albanian'
#    'amharic'
#    'arabic'
#    'armenian'
#    'asturian'
#    'bahasai'
#    'bahasam'
#    'basque'
#    'bengali'
#    'brazilian'
#    'brazil'
#    'breton'
#    'bulgarian'
#    'catalan'
#    'coptic'
#    'croatian'
#    'czech'
#    'danish'
#    'divehi'
#    'dutch'
#    'english'
#    'british'
#    'ukenglish'
#    'esperanto'
#    'estonian'
#    'farsi'
#    'finnish'
#    'french'
#    'friulan'
#    'galician'
#    'german'
#    'austrian'
#    'naustrian'
#    'greek'
#    'hebrew'
#    'hindi'
#    'icelandic'
#    'interlingua'
#    'irish'
#    'italian'
#    'kannada'
#    'lao'
#    'latin'
#    'latvian'
#    'lithuanian'
#    'lsorbian'
#    'magyar'
#    'malayalam'
#    'marathi'
#    'nko'
#    'norsk'
#    'nynorsk'
#    'occitan'
#    'piedmontese'
#    'polish'
#    'portuges'
#    'romanian'
#    'romansh'
#    'russian'
#    'samin'
#    'sanskrit'
#    'scottish'
#    'serbian'
#    'slovak'
#    'slovenian'
#    'spanish'
#    'swedish'
#    'syriac'
#    'tamil'
#    'telugu'
#    'thai'
#    'tibetan'
#    'turkish'
#    'turkmen'
#    'ukrainian'
#    'urdu'
#    'usorbian'
#    'vietnamese'
#    'welsh'
#  ]

Language.get_bigrams = (string) ->
  s = string.toLowerCase()
  s = (s.slice(i, i + 2) for i in [0 ... s.length])
  s.sort()
  return s

Language.string_similarity = (str1, str2) ->
  pairs1 = @get_bigrams(str1)
  pairs2 = @get_bigrams(str2)
  union = pairs1.length + pairs2.length
  hit_count = 0

  while pairs1.length > 0 && pairs2.length > 0
    if pairs1[0] == pairs2[0]
      hit_count++
      pairs1.shift()
      pairs2.shift()
      continue

    if pairs1[0] < pairs2[0]
      pairs1.shift()
    else
      pairs2.shift()

  return (2 * hit_count) / union

Language.lookup = (langcode) ->
  if not @cache[langcode]
    @cache[langcode] = []
    for lc in Language.babelList
      @cache[langcode].push({ lang: lc, sim: @string_similarity(langcode, lc) })
    @cache[langcode].sort((a, b) -> b.sim - a.sim)

  return @cache[langcode]
