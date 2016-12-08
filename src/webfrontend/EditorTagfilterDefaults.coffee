###
 * easydb-editor-tagfilter-defaults
 * Copyright (c) 2013 - 2016 Programmfabrik GmbH
 * MIT Licence
 * https://github.com/programmfabrik/coffeescript-ui, http://www.coffeescript-ui.org
###

class EditorTagfilterDefaults extends CUI.Element
	readOpts: ->
		super()
		BaseConfig.registerPlugin(new BaseConfigEditorTagfilterDefaults())

		filters_by_mask_name = {}
		filters = ez5.session.getBaseConfig().system["editor-tagfilter-defaults"]?.filters or []

		if not filters
			return

		for filter in filters
			mask_name = ez5.mask.CURRENT._mask_by_id[filter.mask_id]?.name

			if not mask_name
				console.warn("EditorTagfilterDefaults: Unable to load mask", filter)
				continue

			if not filter.default or filter.operation.length == 0
				continue

			if not filters_by_mask_name[mask_name]
				filters_by_mask_name[mask_name] = []

			filters_by_mask_name[mask_name].push(filter)

			if filter.tagfilter
				if isString(filter.tagfilter)
					filter.tagfilter = JSON.parse(filter.tagfilter)
			else
				filter.tagfilter = null

			filter.default = JSON.parse(filter.default)


		# console.error "filters by mask name", filters_by_mask_name

		Events.listen
			type: [
				"editor-add-new-result-object"
				"editor-tags-field-changed"
			]

			call: (ev, info) =>
				apply_filters =  filters_by_mask_name[ info.editor_data.mask_name ]
				if not apply_filters
					return

				switch info.editor.getMode()
					when "bulk"
						# not applying filters in bulk more
						return
					when "new"
						operation = "insert"
					when "single"
						operation = "update"

				for apply_filter in apply_filters
					if operation not in apply_filter.operation
						continue

					console.log "editor %c"+ev.getType(), "font-size: 40px;"
					@applyFilter(ev, info, apply_filter)
				return


	applyFilter: (ev, info, filter) ->
		if not info.object
			return

		tagfilter_ok = TagFilter.matchesTags(filter.tagfilter, info.object.getData()._tags)

		console.error "apply Filter", filter, filter.tagfilter, tagfilter_ok

		find_field = (column_id) =>
			for field in info.object.mask.getFields("all")
				if field instanceof MaskSplitter
					continue

				if field.id() == column_id
					return field
			throw("Field not found.")

		if filter.default?.length > 0
			for rule, idx in filter.default
				rule._idx = idx
				rule._tagfilter_match = tagfilter_ok
				switch rule.action
					when "preset"
						field = find_field(rule.column_id)
						console.debug "presetting field", rule, field, info.object.getData()
						field.updateEditorInputValue(ev, rule, info.object.getData())
					else
						console.error("EditorTagfilterDefaults: Skipping unknown action: "+rule.action)

		return





class BaseConfigEditorTagfilterDefaults extends BaseConfigPlugin

	getFieldDefFromParm: (baseConfig, pname, def, parent_def) ->
		console.debug "getFieldDefFromParm:", pname, def, baseConfig.locaKey("parameter")

		switch def.plugin_type
			when "mask-select"
				# sort all masks by objecttype and mask
				mask_ids = []
				get_ot_name = (mask_id) ->
					ez5.schema.CURRENT._table_by_id[ez5.mask.CURRENT._mask_by_id[mask_id].table_id]._name_localized

				get_mask_name = (mask_id) ->
					ez5.mask.CURRENT._mask_by_id[mask_id]._name_localized

				mask_ids = (mask.mask_id for mask in ez5.mask.CURRENT.masks)

				mask_ids.sort (a, b) ->

					a_ot_name = get_ot_name(a)
					b_ot_name = get_ot_name(b)

					if a_ot_name == b_ot_name
						a_mask_name = get_mask_name(a)
						b_mask_name = get_mask_name(b)
						return compareIndex(a_mask_name.toLocaleLowerCase(), b_mask_name.toLocaleLowerCase())

					return compareIndex(a_ot_name.toLocaleLowerCase(), b_ot_name.toLocaleLowerCase())

				mask_opts = []
				last_ot_name = null

				for mask_id in mask_ids
					ot_name = get_ot_name(mask_id)
					mask_name = get_mask_name(mask_id)

					if last_ot_name != ot_name
						mask_opts.push
							label: ot_name
						last_ot_name = ot_name

					mask_opts.push
						text: mask_name
						text_selected: ot_name+": "+mask_name
						value: mask_id

				field =
					type: Select
					options: mask_opts
					name: pname

			when "column-default-value"

				field =
					type: DataTable
					name: pname
					fields: [
						form:
							label: $$(baseConfig.locaKey("parameter")+".type.label")
						type: Select
						name: "action"
						options: [
							text: $$(baseConfig.locaKey("option")+".type.preset")
							value: "preset"
						]
					,
						form:
							label: $$(baseConfig.locaKey("parameter")+".column_id.label")
						type: Select
						name: "column_id"
						options: (df) =>
							mask_id = df.getForm().getDataTable().getData().mask_id
							assert(mask_id > 0, "EditorTagfilterDefaults.column-default-value", "Unable to get mask_id from data table data.", dataField: df)
							mask = ez5.mask.CURRENT._mask_instance_by_name[ez5.mask.CURRENT._mask_by_id[mask_id].name]
							opts = []
							for field in mask.getFields("editor")
								if field instanceof TextColumn
									opts.push
										text: field.nameLocalized()
										value: field.id()
							opts

					,
						form:
							label: $$(baseConfig.locaKey("parameter")+".value.label")
						type: Input
						textarea: true
						name: "value"
					]

			when "tag-filter"

				tf = new TagFilter
					tagForm: ez5.tagForm
					name: pname

				field = tf.getField()


		return field


ez5.session_ready =>
	new EditorTagfilterDefaults()
	console.warn("EditorTagfiltetDefaults LOADED!")