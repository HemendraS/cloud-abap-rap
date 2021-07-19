CLASS /dmo/cl_rap_generator DEFINITION
 PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    TYPES:
            ty_string_table_type TYPE STANDARD TABLE OF string WITH DEFAULT KEY .




    TYPES:
      BEGIN OF ts_condition_components,
        projection_field  TYPE sxco_cds_field_name,
        association_name  TYPE sxco_cds_association_name,
        association_field TYPE sxco_cds_field_name,
      END OF ts_condition_components,


      tt_condition_components TYPE STANDARD TABLE OF ts_condition_components WITH EMPTY KEY.

    TYPES: BEGIN OF t_table_fields,
             field         TYPE sxco_ad_field_name,
             data_element  TYPE sxco_ad_object_name,
             is_key        TYPE abap_bool,
             not_null      TYPE abap_bool,
             currencyCode  TYPE sxco_cds_field_name,
             unitOfMeasure TYPE sxco_cds_field_name,
           END OF t_table_fields.

    TYPES: tt_table_fields TYPE STANDARD TABLE OF t_table_fields WITH KEY field.

    DATA root_node    TYPE REF TO /dmo/cl_rap_node.

    METHODS constructor
      IMPORTING
                json_string TYPE clike
                xco_lib     TYPE REF TO /dmo/cl_rap_xco_lib OPTIONAL
      RAISING   /dmo/cx_rap_generator.


    METHODS generate_bo
      RETURNING
                VALUE(rt_todos) TYPE ty_string_table_type
      RAISING   cx_xco_gen_put_exception
                /dmo/cx_rap_generator.



  PROTECTED SECTION.



  PRIVATE SECTION.

    CONSTANTS method_get_instance_features TYPE if_xco_gen_clas_s_fo_d_section=>tv_method_name  VALUE 'GET_INSTANCE_FEATURES'.
    CONSTANTS method_save_modified TYPE if_xco_gen_clas_s_fo_d_section=>tv_method_name  VALUE 'SAVE_MODIFIED'.

    DATA xco_api  TYPE REF TO /dmo/cl_rap_xco_lib  .

    DATA mo_package      TYPE sxco_package.

********************************************************************************
    "cloud
    DATA mo_environment TYPE REF TO if_xco_cp_gen_env_dev_system.
    DATA mo_put_operation  TYPE REF TO if_xco_cp_gen_d_o_put .
    DATA mo_draft_tabl_put_opertion TYPE REF TO if_xco_cp_gen_d_o_put .
    DATA mo_srvb_put_operation    TYPE REF TO if_xco_cp_gen_d_o_put .
********************************************************************************
    "onpremise
*    DATA mo_environment           TYPE REF TO if_xco_gen_environment .
*    DATA mo_put_operation         TYPE REF TO if_xco_gen_o_mass_put.
*    DATA mo_draft_tabl_put_opertion TYPE REF TO if_xco_gen_o_mass_put.
*    DATA mo_srvb_put_operation    TYPE REF TO if_xco_gen_o_mass_put.
********************************************************************************

    DATA mo_transport TYPE    sxco_transport .

    METHODS assign_package.

    METHODS create_control_structure
      IMPORTING
        VALUE(io_rap_bo_node) TYPE REF TO /dmo/cl_rap_node.

    METHODS create_i_cds_view
      IMPORTING
        VALUE(io_rap_bo_node) TYPE REF TO /dmo/cl_rap_node.

    METHODS create_p_cds_view
      IMPORTING
        VALUE(io_rap_bo_node) TYPE REF TO /dmo/cl_rap_node.

    METHODS create_mde_view
      IMPORTING
        VALUE(io_rap_bo_node) TYPE REF TO /dmo/cl_rap_node.

    METHODS create_draft_table
      IMPORTING
        VALUE(io_rap_bo_node) TYPE REF TO /dmo/cl_rap_node.

    METHODS create_bdef
      IMPORTING
                VALUE(io_rap_bo_node) TYPE REF TO /dmo/cl_rap_node
      RAISING   /dmo/cx_rap_generator.

    METHODS create_bil
      IMPORTING
                VALUE(io_rap_bo_node) TYPE REF TO /dmo/cl_rap_node
      RAISING   /dmo/cx_rap_generator.

    METHODS create_bdef_p
      IMPORTING
        VALUE(io_rap_bo_node) TYPE REF TO /dmo/cl_rap_node.

    METHODS create_condition
      IMPORTING
        VALUE(it_condition_components) TYPE tt_condition_components
      RETURNING
        VALUE(ro_expression)           TYPE REF TO if_xco_ddl_expr_condition.

    METHODS create_service_definition
      IMPORTING
        VALUE(io_rap_bo_node) TYPE REF TO /dmo/cl_rap_node.

    "service binding needs a separate put operation
    METHODS create_service_binding
      IMPORTING
        VALUE(io_rap_bo_node) TYPE REF TO /dmo/cl_rap_node.

    METHODS create_custom_entity
      IMPORTING
        VALUE(io_rap_bo_node) TYPE REF TO /dmo/cl_rap_node.

    METHODS create_custom_query
      IMPORTING
                VALUE(io_rap_bo_node) TYPE REF TO /dmo/cl_rap_node
      RAISING   /dmo/cx_rap_generator.

ENDCLASS.



CLASS /dmo/cl_rap_generator IMPLEMENTATION.


  METHOD assign_package.
    DATA(lo_package_put_operation) = mo_environment->for-devc->create_put_operation( ).
    DATA(lo_specification) = lo_package_put_operation->add_object( mo_package ).
  ENDMETHOD.


  METHOD constructor.

    "in on premise systems one can provide the on premise version
    "of the xco libraries as a parameter

    IF xco_lib IS NOT INITIAL.
      xco_api = xco_lib.
    ELSE.
      xco_api = NEW /dmo/cl_rap_xco_cloud_lib( ).
    ENDIF.

    root_node = NEW /dmo/cl_rap_node(  ).

    root_node->set_is_root_node( io_is_root_node = abap_true ).
    root_node->set_xco_lib( xco_api ).

    DATA(rap_bo_visitor) = NEW /dmo/cl_rap_xco_json_visitor( root_node ).
    DATA(json_data) = xco_cp_json=>data->from_string( json_string ).
    json_data->traverse( rap_bo_visitor ).

    CASE root_node->get_implementation_type( ).
      WHEN /dmo/cl_rap_node=>implementation_type-managed_uuid .
      WHEN /dmo/cl_rap_node=>implementation_type-managed_semantic.
      WHEN /dmo/cl_rap_node=>implementation_type-unmanged_semantic.
      WHEN OTHERS.
        RAISE EXCEPTION TYPE /dmo/cx_rap_generator
          EXPORTING
            textid   = /dmo/cx_rap_generator=>implementation_type_not_valid
            mv_value = root_node->get_implementation_type( ).
    ENDCASE.

    IF root_node->is_consistent(  ) = abap_false.
      RAISE EXCEPTION TYPE /dmo/cx_rap_generator
        EXPORTING
          textid    = /dmo/cx_rap_generator=>node_is_not_consistent
          mv_entity = root_node->entityname.
    ENDIF.
    IF root_node->is_finalized = abap_false.
      RAISE EXCEPTION TYPE /dmo/cx_rap_generator
        EXPORTING
          textid    = /dmo/cx_rap_generator=>node_is_not_finalized
          mv_entity = root_node->entityname.
    ENDIF.
    IF root_node->has_childs(  ).
      LOOP AT root_node->all_childnodes INTO DATA(ls_childnode).
        IF ls_childnode->is_consistent(  ) = abap_false.
          RAISE EXCEPTION TYPE /dmo/cx_rap_generator
            EXPORTING
              textid    = /dmo/cx_rap_generator=>node_is_not_consistent
              mv_entity = ls_childnode->entityname.
        ENDIF.
        IF ls_childnode->is_finalized = abap_false.
          RAISE EXCEPTION TYPE /dmo/cx_rap_generator
            EXPORTING
              textid    = /dmo/cx_rap_generator=>node_is_not_finalized
              mv_entity = ls_childnode->entityname.
        ENDIF.
      ENDLOOP.
    ENDIF.

    mo_package = root_node->package.

    DATA(lo_package) = root_node->xco_lib->get_package( mo_package ).

    IF NOT lo_package->exists( ).

      RAISE EXCEPTION TYPE /dmo/cx_rap_generator
        EXPORTING
          textid   = /dmo/cx_rap_generator=>package_does_not_exist
          mv_value = CONV #( mo_package ).

    ENDIF.



    "Get software component for package
    DATA(lv_package_software_component) = lo_package->read( )-property-software_component->name.

    DATA(lo_transport_layer) = lo_package->read(  )-property-transport_layer.
    DATA(lo_transport_target) = lo_transport_layer->get_transport_target( ).
    DATA(lv_transport_target) = lo_transport_target->value.

    IF root_node->transport_request IS NOT INITIAL.
      mo_transport = root_node->transport_request.
    ELSE.
      DATA(lo_transport_request) = xco_cp_cts=>transports->workbench( lo_transport_target->value  )->create_request( |RAP Business object: { root_node->rap_node_objects-cds_view_i } | ).
      DATA(lv_transport) = lo_transport_request->value.
      mo_transport = lv_transport.
    ENDIF.




**********************************************************************
    "cloud
    mo_environment = xco_cp_generation=>environment->dev_system( mo_transport )  .
    mo_put_operation = mo_environment->create_put_operation( ).
    mo_draft_tabl_put_opertion = mo_environment->create_put_operation( ).
    mo_srvb_put_operation = mo_environment->create_put_operation( ).
**********************************************************************
    "on premise
*    If xco_lib->get_package( root_node->package  )->read( )-property-record_object_changes = abap_true.
*       mo_environment = xco_generation=>environment->transported( mo_transport ).
*    Else.
*      mo_environment = xco_generation=>environment->local.
*    Endif.
*    mo_draft_tabl_put_opertion = mo_environment->create_mass_put_operation( ).
*    mo_put_operation = mo_environment->create_mass_put_operation( ).
*    mo_srvb_put_operation = mo_environment->create_mass_put_operation( ).

**********************************************************************
  ENDMETHOD.


  METHOD create_bdef.

    DATA lv_determination_name TYPE string.
    DATA lv_validation_name TYPE string.


    DATA lt_mapping_header TYPE HASHED TABLE OF  if_xco_gen_bdef_s_fo_b_mapping=>ts_field_mapping
                               WITH UNIQUE KEY cds_view_field dbtable_field.
    DATA ls_mapping_header TYPE if_xco_gen_bdef_s_fo_b_mapping=>ts_field_mapping  .

    DATA lt_mapping_item TYPE HASHED TABLE OF if_xco_gen_bdef_s_fo_b_mapping=>ts_field_mapping
                           WITH UNIQUE KEY cds_view_field dbtable_field.
    DATA ls_mapping_item TYPE if_xco_gen_bdef_s_fo_b_mapping=>ts_field_mapping  .

    lt_mapping_header = io_rap_bo_node->lt_mapping.

    DATA(lo_specification) = mo_put_operation->for-bdef->add_object( io_rap_bo_node->rap_root_node_objects-behavior_definition_i "mo_i_bdef_header
        )->set_package( mo_package
        )->create_form_specification( ).
    lo_specification->set_short_description( |Behavior for { io_rap_bo_node->rap_node_objects-cds_view_i }| ).

    "set implementation type
    CASE io_rap_bo_node->get_implementation_type(  ).
      WHEN /dmo/cl_rap_node=>implementation_type-managed_uuid.
        lo_specification->set_implementation_type( xco_cp_behavior_definition=>implementation_type->managed ).
      WHEN /dmo/cl_rap_node=>implementation_type-managed_semantic.
        lo_specification->set_implementation_type( xco_cp_behavior_definition=>implementation_type->managed ).
      WHEN /dmo/cl_rap_node=>implementation_type-unmanged_semantic.
        lo_specification->set_implementation_type( xco_cp_behavior_definition=>implementation_type->unmanaged ).
    ENDCASE.


    "set is draft enabled
    lo_specification->set_draft_enabled( io_rap_bo_node->draft_enabled ).




    "define behavior for root entity
    DATA(lo_header_behavior) = lo_specification->add_behavior( io_rap_bo_node->rap_node_objects-cds_view_i ).

    " Characteristics.
    DATA(characteristics) = lo_header_behavior->characteristics.
    characteristics->set_alias( CONV #( io_rap_bo_node->rap_node_objects-alias ) ).
    characteristics->set_implementation_class(  io_rap_bo_node->rap_node_objects-behavior_implementation ).

    IF io_rap_bo_node->is_customizing_table = abap_true.
      characteristics->set_with_additional_save( ).
    ENDIF.

**********************************************************************
** Begin of deletion 2105 and 2020
**********************************************************************

*    IF io_rap_bo_node->is_virtual_root(  ) .
*      characteristics->set_with_unmanaged_save( ).
*    ENDIF.

**********************************************************************
** End of deletion 2105 and 2020
**********************************************************************



    IF io_rap_bo_node->draft_enabled = abap_false.
      characteristics->lock->set_master( ).
    ENDIF.

    "@todo add again once setting of
    "authorization master(global)
    "is allowed
    "characteristics->authorization->set_master_instance( ).


    "add the draft table
    IF io_rap_bo_node->draft_enabled = abap_true.
      characteristics->set_draft_table( io_rap_bo_node->draft_table_name ).
    ENDIF.

    IF line_exists( io_rap_bo_node->lt_fields[ name = io_rap_bo_node->field_name-last_changed_at ] ).
      DATA(last_changed_at) = io_rap_bo_node->lt_fields[ name = io_rap_bo_node->field_name-last_changed_at ]-cds_view_field.
    ELSEIF line_exists( io_rap_bo_node->lt_additional_fields[ name = io_rap_bo_node->field_name-last_changed_at ] ).
      last_changed_at = io_rap_bo_node->lt_additional_fields[ name = io_rap_bo_node->field_name-last_changed_at ]-cds_view_field.
    ENDIF.

    IF line_exists( io_rap_bo_node->lt_fields[ name = io_rap_bo_node->field_name-local_instance_last_changed_at ] ).
      DATA(local_instance_last_changed_at) = io_rap_bo_node->lt_fields[ name = io_rap_bo_node->field_name-local_instance_last_changed_at ]-cds_view_field.
    ELSEIF line_exists( io_rap_bo_node->lt_additional_fields[ name = io_rap_bo_node->field_name-local_instance_last_changed_at ] ).
      local_instance_last_changed_at = io_rap_bo_node->lt_fields[ name = io_rap_bo_node->field_name-local_instance_last_changed_at ].
    ENDIF.

    IF io_rap_bo_node->draft_enabled = abap_true.
      characteristics->etag->set_master( CONV sxco_cds_field_name( local_instance_last_changed_at ) ).
**********************************************************************
** Begin of deletion 2020
**********************************************************************
      characteristics->lock->set_master_total_etag( CONV sxco_cds_field_name( last_changed_at ) ).
**********************************************************************
** End of deletion 2020
**********************************************************************
    ELSE.
      characteristics->etag->set_master( CONV sxco_cds_field_name( last_changed_at ) ).
      characteristics->lock->set_master( ).
    ENDIF.

    CASE io_rap_bo_node->get_implementation_type(  ).
      WHEN /dmo/cl_rap_node=>implementation_type-managed_uuid.
        lo_header_behavior->characteristics->set_persistent_table( CONV sxco_dbt_object_name( io_rap_bo_node->persistent_table_name ) ).
      WHEN /dmo/cl_rap_node=>implementation_type-managed_semantic.
        lo_header_behavior->characteristics->set_persistent_table( CONV sxco_dbt_object_name( io_rap_bo_node->persistent_table_name ) ).
      WHEN /dmo/cl_rap_node=>implementation_type-unmanged_semantic.
        "do not set a persistent table
    ENDCASE.

    IF io_rap_bo_node->draft_enabled = abap_true.

      "  if this is set, no BIL is needed in a plain vanilla managed BO
      "  add the following operations in case draft is used
      "  draft action Edit;
      "  draft action Activate;
      "  draft action Discard;
      "  draft action Resume;
      "  draft determine action Prepare;

**********************************************************************
** Begin of deletion 2020
**********************************************************************

      lo_header_behavior->add_action( 'Edit'  )->set_draft( ).
      lo_header_behavior->add_action( 'Activate'  )->set_draft( ).
      lo_header_behavior->add_action( 'Discard'  )->set_draft( ).
      lo_header_behavior->add_action( 'Resume'  )->set_draft( ).
      lo_header_behavior->add_action( 'Prepare'  )->set_draft( )->set_determine( ).

**********************************************************************
** End of deletion 2020
**********************************************************************


    ELSE.

      " add standard operations for root node
      " in case no draft is used

      lo_header_behavior->add_standard_operation( xco_cp_behavior_definition=>standard_operation->create ).
      lo_header_behavior->add_standard_operation( xco_cp_behavior_definition=>standard_operation->update ).
      lo_header_behavior->add_standard_operation( xco_cp_behavior_definition=>standard_operation->delete ).

    ENDIF.

**********************************************************************
** Begin of deletion 2020
**********************************************************************
    IF io_rap_bo_node->is_customizing_table = abap_true.

      lv_validation_name = |val_transport| .

      lo_header_behavior->add_validation( CONV #( lv_validation_name ) "'val_transport'
        )->set_time( xco_cp_behavior_definition=>evaluation->time->on_save
        )->set_trigger_operations( VALUE #( ( xco_cp_behavior_definition=>evaluation->trigger_operation->create )
                                            ( xco_cp_behavior_definition=>evaluation->trigger_operation->update )
"                                              ( xco_cp_behavior_definition=>evaluation->trigger_operation->delete )
                                          )  ).
    ENDIF.
**********************************************************************
** End of deletion 2020
**********************************************************************



    CASE io_rap_bo_node->get_implementation_type(  ).
      WHEN /dmo/cl_rap_node=>implementation_type-managed_uuid.

        lv_determination_name = |Calculate{ io_rap_bo_node->object_id_cds_field_name }| .

        lo_header_behavior->add_determination( CONV #( lv_determination_name ) "'CalculateSemanticKey'
          )->set_time( xco_cp_behavior_definition=>evaluation->time->on_save
          )->set_trigger_operations( VALUE #( ( xco_cp_behavior_definition=>evaluation->trigger_operation->create ) )  ).




        LOOP AT lt_mapping_header INTO ls_mapping_header.
          CASE ls_mapping_header-dbtable_field.
            WHEN io_rap_bo_node->field_name-uuid.
              lo_header_behavior->add_field( ls_mapping_header-cds_view_field
                               )->set_numbering_managed( ).
            WHEN  io_rap_bo_node->object_id .
              lo_header_behavior->add_field( ls_mapping_header-cds_view_field
                                 )->set_read_only( ).
          ENDCASE.
        ENDLOOP.

      WHEN /dmo/cl_rap_node=>implementation_type-managed_semantic.

        "no specific settings needed for managed_semantic until draft would be supported

        "xco libraries do not yet support
        "field ( readonly : update ) HolidayID;

      WHEN /dmo/cl_rap_node=>implementation_type-unmanged_semantic.

        LOOP AT io_rap_bo_node->lt_fields INTO DATA(ls_field) WHERE name <> io_rap_bo_node->field_name-client.
          IF ls_field-key_indicator = abap_true.
            lo_header_behavior->add_field( ls_field-cds_view_field
                               )->set_read_only(
                               ).
          ENDIF.
        ENDLOOP.
    ENDCASE.

    " if io_rap_bo_node->


    IF lt_mapping_header IS NOT INITIAL.
      CASE io_rap_bo_node->get_implementation_type(  ).
        WHEN /dmo/cl_rap_node=>implementation_type-managed_uuid.
          lo_header_behavior->add_mapping_for( CONV sxco_dbt_object_name( io_rap_bo_node->persistent_table_name ) )->set_field_mapping( it_field_mappings =  lt_mapping_header ).
        WHEN /dmo/cl_rap_node=>implementation_type-managed_semantic.
          lo_header_behavior->add_mapping_for( CONV sxco_dbt_object_name( io_rap_bo_node->persistent_table_name ) )->set_field_mapping( it_field_mappings =  lt_mapping_header ).
        WHEN /dmo/cl_rap_node=>implementation_type-unmanged_semantic.
          "add control structure
          lo_header_behavior->add_mapping_for( CONV sxco_dbt_object_name( io_rap_bo_node->persistent_table_name ) )->set_field_mapping( it_field_mappings =  lt_mapping_header )->set_control( io_rap_bo_node->rap_node_objects-control_structure ).

      ENDCASE.
    ENDIF.

    IF io_rap_bo_node->has_childs(  ).
      LOOP AT io_rap_bo_node->childnodes INTO DATA(lo_childnode).
        DATA(assoc) = lo_header_behavior->add_association( '_' && lo_childnode->rap_node_objects-alias  ).
        assoc->set_create_enabled(  ).
        assoc->set_draft_enabled( io_rap_bo_node->draft_enabled ).
      ENDLOOP.
    ENDIF.



    "define behavior for child entities

    IF io_rap_bo_node->has_childs(  ).

      LOOP AT io_rap_bo_node->all_childnodes INTO lo_childnode.

        CLEAR lt_mapping_item.

        lt_mapping_item = lo_childnode->lt_mapping.

        DATA(lo_item_behavior) = lo_specification->add_behavior( lo_childnode->rap_node_objects-cds_view_i ).

        " Characteristics.
        DATA(item_characteristics) = lo_item_behavior->characteristics.

        "add the draft table
        IF io_rap_bo_node->draft_enabled = abap_true.
          item_characteristics->set_draft_table( lo_childnode->draft_table_name ).
        ENDIF.

        "@todo: Compare with code for root entity

        IF line_exists( lo_childnode->lt_fields[ name = lo_childnode->field_name-local_instance_last_changed_at ] ).
          local_instance_last_changed_at = lo_childnode->lt_fields[ name = lo_childnode->field_name-local_instance_last_changed_at ]-cds_view_field.
        ELSEIF line_exists( lo_childnode->lt_additional_fields[ name = lo_childnode->field_name-local_instance_last_changed_at ] ).
          local_instance_last_changed_at = lo_childnode->lt_additional_fields[ name = lo_childnode->field_name-local_instance_last_changed_at ]-cds_view_field.
        ENDIF.


        IF io_rap_bo_node->draft_enabled = abap_true.
          item_characteristics->etag->set_master( CONV sxco_cds_field_name( local_instance_last_changed_at ) ).
        ENDIF.


        "set key fields of parent entity in child entity as read only
        "because they are set via create by association

        CASE lo_childnode->get_implementation_type(  ).
          WHEN /dmo/cl_rap_node=>implementation_type-managed_semantic.
            LOOP AT lo_childnode->lt_fields INTO DATA(ls_key_field_child) WHERE key_indicator = abap_true
                                                                            AND name <> io_rap_bo_node->field_name-client.
              LOOP AT io_rap_bo_node->lt_fields INTO DATA(ls_key_field) WHERE key_indicator = abap_true
                                                                          AND name = ls_key_field_child-name.
                lo_item_behavior->add_field( ls_key_field-cds_view_field
                                             )->set_read_only( ).
              ENDLOOP.
            ENDLOOP.
        ENDCASE.

        " Characteristics.
        IF lo_childnode->is_grand_child_or_deeper(  ).

          item_characteristics->set_alias( CONV #( lo_childnode->rap_node_objects-alias )
            )->set_implementation_class( lo_childnode->rap_node_objects-behavior_implementation
            )->lock->set_dependent_by( '_' && lo_childnode->root_node->rap_node_objects-alias  ).

          "@todo add again once setting of
          "authorization master(global)
          "is allowed
          "      item_characteristics->authorization->set_dependent_by( '_' && lo_childnode->root_node->rap_node_objects-alias  ).


          CASE lo_childnode->get_implementation_type(  ).
            WHEN /dmo/cl_rap_node=>implementation_type-managed_uuid.
              item_characteristics->set_persistent_table( CONV sxco_dbt_object_name( lo_childnode->persistent_table_name ) ).
            WHEN   /dmo/cl_rap_node=>implementation_type-managed_semantic.
              item_characteristics->set_persistent_table( CONV sxco_dbt_object_name( lo_childnode->persistent_table_name ) ).
            WHEN /dmo/cl_rap_node=>implementation_type-unmanged_semantic.
              "nothing to do
          ENDCASE.



          "add association to parent node
          assoc = lo_item_behavior->add_association( '_' && lo_childnode->parent_node->rap_node_objects-alias  ).
          assoc->set_draft_enabled( io_rap_bo_node->draft_enabled ).


        ELSEIF lo_childnode->is_child(  ).

          item_characteristics->set_alias( CONV #( lo_childnode->rap_node_objects-alias )
                   )->set_implementation_class( lo_childnode->rap_node_objects-behavior_implementation
                   )->lock->set_dependent_by( '_' && lo_childnode->parent_node->rap_node_objects-alias  ).


          "@todo add again once setting of
          "authorization master(global)
          "is allowed
          "      item_characteristics->authorization->set_dependent_by( '_' && lo_childnode->parent_node->rap_node_objects-alias  ).

          IF lo_childnode->root_node->is_customizing_table = abap_true.
            item_characteristics->set_with_additional_save( ).
          ENDIF.


          CASE lo_childnode->get_implementation_type(  ).
            WHEN /dmo/cl_rap_node=>implementation_type-managed_uuid.
              item_characteristics->set_persistent_table( CONV sxco_dbt_object_name( lo_childnode->persistent_table_name ) ).
            WHEN   /dmo/cl_rap_node=>implementation_type-managed_semantic.
              item_characteristics->set_persistent_table( CONV sxco_dbt_object_name( lo_childnode->persistent_table_name  ) ).
            WHEN /dmo/cl_rap_node=>implementation_type-unmanged_semantic.
              "set no persistent table
          ENDCASE.


          "add association to parent node
          assoc = lo_item_behavior->add_association( '_' && lo_childnode->parent_node->rap_node_objects-alias  ).
          assoc->set_draft_enabled( io_rap_bo_node->draft_enabled ).

        ELSE.
          "should not happen

          RAISE EXCEPTION TYPE /dmo/cx_rap_generator
            MESSAGE ID '/DMO/CM_RAP_GEN_MSG' TYPE 'E' NUMBER '001'
            WITH lo_childnode->entityname lo_childnode->root_node->entityname.

        ENDIF.


        IF lo_childnode->has_childs(  ).
          LOOP AT lo_childnode->childnodes INTO DATA(lo_grandchildnode).
            assoc = lo_item_behavior->add_association( '_' && lo_grandchildnode->rap_node_objects-alias  ).
            assoc->set_create_enabled(  ).
            assoc->set_draft_enabled( io_rap_bo_node->draft_enabled ).
          ENDLOOP.
        ENDIF.

        "child nodes only offer update and delete and create by assocation
        lo_item_behavior->add_standard_operation( xco_cp_behavior_definition=>standard_operation->update ).
        lo_item_behavior->add_standard_operation( xco_cp_behavior_definition=>standard_operation->delete ).



**********************************************************************
** Begin of deletion 2020
**********************************************************************
        IF io_rap_bo_node->is_customizing_table = abap_true.

          lv_validation_name = |val_transport| .

          lo_item_behavior->add_validation( CONV #( lv_validation_name ) "'val_transport'
            )->set_time( xco_cp_behavior_definition=>evaluation->time->on_save
            )->set_trigger_operations( VALUE #( ( xco_cp_behavior_definition=>evaluation->trigger_operation->create )
                                                ( xco_cp_behavior_definition=>evaluation->trigger_operation->update )
    "                                              ( xco_cp_behavior_definition=>evaluation->trigger_operation->delete )
                                              )  ).
        ENDIF.
**********************************************************************
** End of deletion 2020
**********************************************************************


        CASE lo_childnode->get_implementation_type(  ).
          WHEN /dmo/cl_rap_node=>implementation_type-managed_uuid.
            "determination CalculateSemanticKey on modify { create; }
            lv_determination_name = 'Calculate' && lo_childnode->object_id_cds_field_name.

            lo_item_behavior->add_determination( CONV #( lv_determination_name )
              )->set_time( xco_cp_behavior_definition=>evaluation->time->on_save
              )->set_trigger_operations( VALUE #( ( xco_cp_behavior_definition=>evaluation->trigger_operation->create ) )  ).

            LOOP AT lt_mapping_item INTO ls_mapping_item.
              CASE ls_mapping_item-dbtable_field.
                WHEN lo_childnode->field_name-uuid.
                  lo_item_behavior->add_field( ls_mapping_item-cds_view_field
                                 )->set_numbering_managed( ).
                WHEN lo_childnode->field_name-parent_uuid OR
                     lo_childnode->field_name-root_uuid .
                  lo_item_behavior->add_field( ls_mapping_item-cds_view_field )->set_read_only( ).

                WHEN  lo_childnode->object_id.
                  lo_item_behavior->add_field( ls_mapping_item-cds_view_field )->set_read_only( ).

              ENDCASE.
            ENDLOOP.

          WHEN /dmo/cl_rap_node=>implementation_type-managed_semantic.

            "key field is not set as read only since at this point we assume
            "that the key is set externally

            IF lo_childnode->root_node->is_virtual_root(  ).
              lo_item_behavior->add_field( lo_childnode->singleton_field_name )->set_read_only( ).
            ENDIF.

          WHEN /dmo/cl_rap_node=>implementation_type-unmanged_semantic.
            "make the key fields read only in the child entities
            "Otherwise you get the warning
            "The field "<semantic key of root node>" is used for "lock" dependency (in the ON clause of
            "the association "_Travel"). This means it should be flagged as
            "readonly / readonly:update".

            "LOOP AT lo_childnode->root_node->lt_fields INTO DATA(ls_fields)
            LOOP AT lo_childnode->lt_fields INTO DATA(ls_fields)
              WHERE key_indicator = abap_true AND name <> lo_childnode->field_name-client.
              lo_item_behavior->add_field( ls_fields-cds_view_field )->set_read_only( ).
            ENDLOOP.



        ENDCASE.

        IF lt_mapping_item IS NOT INITIAL.
          CASE io_rap_bo_node->get_implementation_type(  ).
            WHEN /dmo/cl_rap_node=>implementation_type-managed_uuid.
              lo_item_behavior->add_mapping_for( CONV sxco_dbt_object_name( lo_childnode->persistent_table_name ) )->set_field_mapping( it_field_mappings =  lt_mapping_item ).
            WHEN /dmo/cl_rap_node=>implementation_type-managed_semantic.
              lo_item_behavior->add_mapping_for( CONV sxco_dbt_object_name( lo_childnode->persistent_table_name ) )->set_field_mapping( it_field_mappings =  lt_mapping_item ).
            WHEN /dmo/cl_rap_node=>implementation_type-unmanged_semantic.
              "add control structure
              IF io_rap_bo_node->data_source_name = io_rap_bo_node->data_source_types-table.
                lo_item_behavior->add_mapping_for( CONV sxco_dbt_object_name( lo_childnode->persistent_table_name ) )->set_field_mapping( it_field_mappings =  lt_mapping_item )->set_control( lo_childnode->rap_node_objects-control_structure ).
              ELSEIF io_rap_bo_node->data_source_name = io_rap_bo_node->data_source_types-structure.
                lo_item_behavior->add_mapping_for( CONV sxco_dbt_object_name( lo_childnode->structure_name ) )->set_field_mapping( it_field_mappings =  lt_mapping_item )->set_control( lo_childnode->rap_node_objects-control_structure ).
              ELSEIF io_rap_bo_node->data_source_name = io_rap_bo_node->data_source_types-abap_type.
                "@todo
                "check how abap_type is used
              ENDIF.
          ENDCASE.
        ENDIF.



      ENDLOOP.

    ENDIF.


  ENDMETHOD.


  METHOD create_bdef_p.
    DATA(lo_specification) = mo_put_operation->for-bdef->add_object( io_rap_bo_node->rap_root_node_objects-behavior_definition_p
               )->set_package( mo_package
               )->create_form_specification( ).



    lo_specification->set_short_description( |Behavior for { io_rap_bo_node->rap_node_objects-cds_view_p }|
       )->set_implementation_type( xco_cp_behavior_definition=>implementation_type->projection
       ).

**********************************************************************
** Begin of deletion 2020
**********************************************************************
    IF io_rap_bo_node->draft_enabled = abap_true.
      lo_specification->set_use_draft( ).
    ENDIF.
**********************************************************************
** End of deletion 2020
**********************************************************************

    DATA(lo_header_behavior) = lo_specification->add_behavior( io_rap_bo_node->rap_node_objects-cds_view_p ).

    " Characteristics.
    lo_header_behavior->characteristics->set_alias( CONV #( io_rap_bo_node->rap_node_objects-alias )
      ).
    IF io_rap_bo_node->draft_enabled = abap_true.

      "add the following actions in case draft is used
      "follows the strict implementation principle
      "use action Activate;
      "use action Discard;
      "use action Edit;
      "use action Prepare;
      "use action Resume;

      lo_header_behavior->add_action( 'Edit' )->set_use( ).
      lo_header_behavior->add_action( 'Activate' )->set_use( ).
      lo_header_behavior->add_action( 'Discard' )->set_use( ).
      lo_header_behavior->add_action( 'Resume' )->set_use( ).
      lo_header_behavior->add_action( 'Prepare' )->set_use( ).


    ELSE.
      " Standard operations.
      lo_header_behavior->add_standard_operation( xco_cp_behavior_definition=>standard_operation->create )->set_use( ).
      lo_header_behavior->add_standard_operation( xco_cp_behavior_definition=>standard_operation->update )->set_use( ).
      lo_header_behavior->add_standard_operation( xco_cp_behavior_definition=>standard_operation->delete )->set_use( ).
    ENDIF.

    "use action Edit;
    "if the Edit function is defined there is no need to implement a BIL
    "IF io_rap_bo_node->draft_enabled = abap_true.
    "  lo_header_behavior->add_action( iv_name = 'Edit' )->set_use( ).
    "ENDIF.

    IF io_rap_bo_node->has_childs(  ).

      LOOP AT io_rap_bo_node->childnodes INTO DATA(lo_childnode).
        DATA(assoc) =  lo_header_behavior->add_association( '_' && lo_childnode->rap_node_objects-alias ).
        assoc->set_create_enabled( abap_true ).
        assoc->set_use(  ).
        assoc->set_draft_enabled( io_rap_bo_node->draft_enabled ).
      ENDLOOP.

      LOOP AT io_rap_bo_node->all_childnodes INTO lo_childnode.

        DATA(lo_item_behavior) = lo_specification->add_behavior( lo_childnode->rap_node_objects-cds_view_p ).

        " Characteristics.
        lo_item_behavior->characteristics->set_alias( CONV #( lo_childnode->rap_node_objects-alias )
          ).
        " Standard operations.
        lo_item_behavior->add_standard_operation( xco_cp_behavior_definition=>standard_operation->update )->set_use( ).
        lo_item_behavior->add_standard_operation( xco_cp_behavior_definition=>standard_operation->delete )->set_use( ).

        IF lo_childnode->is_grand_child_or_deeper(  ).
          "lo_item_behavior->add_association(  mo_assoc_to_root )->set_use(  ).
          "'_' && lo_childnode->root_node->rap_node_objects-alias
          assoc = lo_item_behavior->add_association(  '_' && lo_childnode->root_node->rap_node_objects-alias ).
          assoc->set_use( ).
          assoc->set_draft_enabled( io_rap_bo_node->draft_enabled ).
          "lo_item_behavior->add_association(  '_' && lo_childnode->root_node->rap_node_objects-alias )->set_use(  )->set_draft_enabled( io_rap_bo_node->draft_enabled ).
        ELSEIF lo_childnode->is_child( ).
          "lo_item_behavior->add_association(  mo_assoc_to_header )->set_use(  ).
          "'_' && lo_childnode->parent_node->rap_node_objects-alias
          assoc = lo_item_behavior->add_association(  '_' && lo_childnode->parent_node->rap_node_objects-alias ).
          assoc->set_use(  ).
          assoc->set_draft_enabled( io_rap_bo_node->draft_enabled ).
        ELSE.


        ENDIF.
        IF lo_childnode->has_childs(  ).
          LOOP AT lo_childnode->childnodes INTO DATA(lo_grandchildnode).
            assoc = lo_item_behavior->add_association( iv_name = '_' && lo_grandchildnode->rap_node_objects-alias ).
            assoc->set_create_enabled(  ).
            assoc->set_use(  ).
            assoc->set_draft_enabled( io_rap_bo_node->draft_enabled ).
          ENDLOOP.
        ENDIF.

      ENDLOOP.

    ENDIF.


  ENDMETHOD.


  METHOD create_bil.
**********************************************************************
** Begin of deletion 2020
**********************************************************************

    DATA  source_method_save_modified  TYPE if_xco_gen_clas_s_fo_i_method=>tt_source  .
    DATA  source_method_validation  TYPE if_xco_gen_clas_s_fo_i_method=>tt_source  .
    DATA  source_code_line LIKE LINE OF source_method_save_modified.




    DATA(lo_specification) = mo_put_operation->for-clas->add_object(  io_rap_bo_node->rap_node_objects-behavior_implementation
                                    )->set_package( mo_package
                                    )->create_form_specification( ).


    lo_specification->set_short_description( 'Behavior implementation' ).

    "behavior has to be defined for the root node in all BIL classes
    "to_upper( ) as workaround for 2011 and 2020, fix will be available with 2102
    lo_specification->definition->set_abstract(
      )->set_for_behavior_of( to_upper( io_rap_bo_node->root_node->rap_node_objects-cds_view_i ) ).

*    DATA(lo_handler) = lo_specification->add_local_class( 'LCL_HANDLER' ).
*    lo_handler->definition->set_superclass( 'CL_ABAP_BEHAVIOR_HANDLER' ).

    "a local class will only be created if there are methods
    "that are generated as well
    "otherwise we get the error
    "The BEHAVIOR class "LCL_HANDLER" does not contain the BEHAVIOR method "MODIFY | READ".

    IF ( io_rap_bo_node->is_root(  ) = abap_true AND
        io_rap_bo_node->draft_enabled = abap_true ) OR
        io_rap_bo_node->get_implementation_type(  )  = /dmo/cl_rap_node=>implementation_type-managed_uuid OR
         io_rap_bo_node->is_customizing_table = abap_true.

      DATA(lo_handler) = lo_specification->add_local_class( 'LCL_HANDLER' ).
      lo_handler->definition->set_superclass( 'CL_ABAP_BEHAVIOR_HANDLER' ).

    ENDIF.


    "Method Edit is called implicitly (features:instance)
    IF io_rap_bo_node->is_root(  ) = abap_true AND
       io_rap_bo_node->draft_enabled = abap_true.

      " method get_instance_features.
      DATA(lo_get_features) = lo_handler->definition->section-private->add_method( method_get_instance_features ).
      lo_get_features->behavior_implementation->set_result( iv_result = 'result' ).
      lo_get_features->behavior_implementation->set_for_instance_features( ).

      DATA(lo_keys_get_features)  = lo_get_features->add_importing_parameter( iv_name = 'keys' ).
      lo_keys_get_features->behavior_implementation->set_for( iv_for = io_rap_bo_node->entityname ).
      lo_keys_get_features->behavior_implementation->set_request( iv_request = 'requested_features' ).

      lo_handler->implementation->add_method( method_get_instance_features ).
    ENDIF.

    "in case of a semantic key scenario the keys are set externally
    IF io_rap_bo_node->get_implementation_type(  )  = /dmo/cl_rap_node=>implementation_type-managed_uuid.

      "method determination
      DATA(lv_determination_name) = |Calculate{ io_rap_bo_node->object_id_cds_field_name }| .

      DATA(lo_det) = lo_handler->definition->section-private->add_method( CONV #( lv_determination_name ) ).
      lo_det->behavior_implementation->set_for_determine_on_save( ).

      DATA(lo_keys_determination) = lo_det->add_importing_parameter( iv_name = 'keys' ).
      lo_keys_determination->behavior_implementation->set_for( iv_for = | { io_rap_bo_node->entityname }~{ lv_determination_name } | ).

      lo_handler->implementation->add_method( CONV #( lv_determination_name ) ).

    ENDIF.

    IF io_rap_bo_node->is_customizing_table = abap_true.


      "SELECT * FROM @io_rap_bo_node->lt_fields AS fields WHERE name  = @io_rap_bo_node->field_name-uuid INTO TABLE @DATA(result_uuid).

      SELECT * FROM @io_rap_bo_node->lt_fields AS fields WHERE key_indicator  = @abap_true
                                                           AND name <> @io_rap_bo_node->field_name-client INTO TABLE @DATA(key_fields).



      DATA(lv_validation_name) = |val_transport| .

      DATA(lo_val) = lo_handler->definition->section-private->add_method( CONV #( lv_validation_name ) ).
      lo_val->behavior_implementation->set_for_validate_on_save( ).
      DATA(lo_keys_validation) = lo_val->add_importing_parameter( iv_name = 'keys' ).
      lo_keys_validation->behavior_implementation->set_for( iv_for = | { io_rap_bo_node->entityname }~{ lv_validation_name } | ).

      CLEAR source_method_validation.

      APPEND |CHECK lines( keys ) > 0.| TO source_method_validation.
      APPEND |DATA table_keys TYPE TABLE OF { to_upper( io_rap_bo_node->table_name ) } .  |  TO source_method_validation.
      APPEND |table_keys = VALUE #( FOR key IN keys (  |  TO source_method_validation.

      LOOP AT key_fields INTO DATA(key_field).
        APPEND |         { key_field-name } = key-{ key_field-cds_view_field  }        |  TO source_method_validation.
      ENDLOOP.

      APPEND |) ).  |  TO source_method_validation.
      APPEND |TRY.|  TO source_method_validation.
      APPEND |    cl_a4c_bc_factory=>get_handler( )->add_to_transport_request(|  TO source_method_validation.
      APPEND |          EXPORTING|  TO source_method_validation.
      APPEND |            iv_check_mode         = abap_true  |  TO source_method_validation.
      APPEND |            it_object_tables      = VALUE #( ( objname = '{ to_upper( io_rap_bo_node->table_name ) }'  |  TO source_method_validation.
      APPEND |                                               tabkeys = REF #( table_keys )  ) )|  TO source_method_validation.
      APPEND |            iv_mandant_field_name = '{ io_rap_bo_node->field_name-client }'  |  TO source_method_validation.
      APPEND |          IMPORTING|  TO source_method_validation.
      APPEND |            rt_messages           = DATA(messages)|  TO source_method_validation.
      APPEND |            rv_success            = DATA(success) ).|  TO source_method_validation.
      APPEND |  CATCH cx_a4c_bc_exception INTO DATA(exc).|  TO source_method_validation.
      APPEND |    success = abap_false.|  TO source_method_validation.
      APPEND |ENDTRY.|  TO source_method_validation.
      APPEND |IF success NE 'S'.|  TO source_method_validation.
      APPEND |  failed-{ io_rap_bo_node->entityname } = CORRESPONDING #( keys ).  |  TO source_method_validation.
      APPEND |  DATA report LIKE LINE OF reported-{ io_rap_bo_node->entityname }.  |  TO source_method_validation.
      APPEND |  report = CORRESPONDING #( keys[ 1 ] ).|  TO source_method_validation.
      APPEND |  IF exc IS BOUND.|  TO source_method_validation.
      APPEND |    report-%msg = new_message_with_text( text = exc->get_text( ) ).|  TO source_method_validation.
      APPEND |    INSERT report INTO TABLE reported-{ io_rap_bo_node->entityname }.  |  TO source_method_validation.
      APPEND |  ENDIF.|  TO source_method_validation.
      APPEND |  LOOP AT messages ASSIGNING FIELD-SYMBOL(<msg>).|  TO source_method_validation.
      APPEND |    report-%msg = new_message(|  TO source_method_validation.
      APPEND |                    id       = <msg>-msgid|  TO source_method_validation.
      APPEND |                    number   = <msg>-msgno|  TO source_method_validation.
      APPEND |                    severity = CONV #( <msg>-msgty )|  TO source_method_validation.
      APPEND |                    v1       = <msg>-msgv1|  TO source_method_validation.
      APPEND |                    v2       = <msg>-msgv2|  TO source_method_validation.
      APPEND |                    v3       = <msg>-msgv3|  TO source_method_validation.
      APPEND |                    v4       = <msg>-msgv4 ).|  TO source_method_validation.
      APPEND |    INSERT report INTO TABLE reported-{ io_rap_bo_node->entityname }.  |  TO source_method_validation.
      APPEND |  ENDLOOP.|  TO source_method_validation.
      APPEND |ENDIF.|  TO source_method_validation.


      lo_handler->implementation->add_method( CONV #( lv_validation_name ) )->set_source( source_method_validation ).
    ENDIF.

    IF io_rap_bo_node->is_customizing_table = abap_true.

      DATA(lo_saver) = lo_specification->add_local_class( 'LCL_SAVER' ).
      lo_saver->definition->set_superclass( 'CL_ABAP_BEHAVIOR_SAVER' ).
      lo_saver->definition->section-protected->add_method( method_save_modified )->set_redefinition( ).


      IF io_rap_bo_node->is_root(  ) = abap_true.

        CLEAR source_method_save_modified.
        APPEND | DATA table_keys TYPE TABLE OF { to_upper( io_rap_bo_node->table_name ) }.  | TO source_method_save_modified.
        APPEND | DATA object_tables TYPE if_a4c_bc_handler=>tt_object_tables.| TO source_method_save_modified.
        APPEND | table_keys = VALUE #( FOR key IN create-{ io_rap_bo_node->entityname } ( | TO source_method_save_modified.

        LOOP AT key_fields INTO key_field.
          APPEND |         { key_field-name } = key-{ key_field-cds_view_field }        |  TO source_method_save_modified.
        ENDLOOP.

        APPEND | ) ).  | TO source_method_save_modified.
        APPEND | LOOP AT update-holiday ASSIGNING FIELD-SYMBOL(<update>).  | TO source_method_save_modified.
        APPEND |   INSERT VALUE #( | TO source_method_save_modified.

        LOOP AT key_fields INTO key_field.
          APPEND |         { key_field-name } = <update>-{ key_field-cds_view_field  }        |  TO source_method_save_modified.
        ENDLOOP.

        APPEND | ) INTO TABLE table_keys.  | TO source_method_save_modified.
        APPEND | ENDLOOP.| TO source_method_save_modified.
        APPEND | LOOP AT delete-{ io_rap_bo_node->entityname } ASSIGNING FIELD-SYMBOL(<delete>).  | TO source_method_save_modified.
        APPEND |   INSERT VALUE #( | TO source_method_save_modified.

        LOOP AT key_fields INTO key_field.
          APPEND |         { key_Field-name } = <delete>-{ key_field-cds_view_field  }        |  TO source_method_save_modified.
        ENDLOOP.

        APPEND | ) INTO TABLE table_keys.  | TO source_method_save_modified.
        APPEND | ENDLOOP.| TO source_method_save_modified.
        APPEND | IF table_keys IS NOT INITIAL.| TO source_method_save_modified.
        APPEND |   INSERT VALUE #( objname = '{ to_upper( io_rap_bo_node->table_name ) }'  | TO source_method_save_modified.
        APPEND |                   tabkeys = REF #( table_keys ) ) INTO TABLE object_Tables.| TO source_method_save_modified.
        APPEND | ENDIF.| TO source_method_save_modified.

        APPEND | CHECK object_tables IS NOT INITIAL.| TO source_method_save_modified.
        APPEND | TRY.| TO source_method_save_modified.
        APPEND |     cl_a4c_bc_factory=>get_handler( )->add_to_transport_request(| TO source_method_save_modified.
        APPEND |           EXPORTING| TO source_method_save_modified.
        APPEND |             iv_check_mode         = abap_false  | TO source_method_save_modified.
        APPEND |             it_object_tables      = object_tables| TO source_method_save_modified.
        APPEND |             iv_mandant_field_name = '{ io_rap_bo_node->field_name-client }'  | TO source_method_save_modified.
        APPEND |           IMPORTING| TO source_method_save_modified.
        APPEND |             rv_success            = DATA(success) ).| TO source_method_save_modified.
        APPEND |   CATCH cx_a4c_bc_exception.| TO source_method_save_modified.
        APPEND |     success = abap_false.| TO source_method_save_modified.
        APPEND | ENDTRY.| TO source_method_save_modified.
        APPEND | ASSERT success = 'S'. "point of no return - previous validation must catch all exceptions| TO source_method_save_modified.

        lo_saver->implementation->add_method(  method_save_modified  )->set_source( source_method_save_modified ).


      ELSEIF io_rap_bo_node->is_child(  ) = abap_true.

        CLEAR source_method_save_modified.

        APPEND | DATA table_keys TYPE TABLE OF { to_upper( io_rap_bo_node->root_node->table_name ) }.  | TO source_method_save_modified.
        APPEND | DATA table_keys_txt TYPE TABLE OF { to_upper( io_rap_bo_node->table_name ) }.  | TO source_method_save_modified.
        APPEND | DATA object_tables TYPE if_a4c_bc_handler=>tt_object_tables.| TO source_method_save_modified.
        APPEND | table_keys_txt = VALUE #( FOR key_txt IN create-{ io_rap_bo_node->entityname } ( | TO source_method_save_modified.


        LOOP AT key_fields INTO key_field.
          APPEND |         { key_field-name } = key_txt-{ key_field-cds_view_field }        |  TO source_method_save_modified.
        ENDLOOP.

        APPEND | ) ).  | TO source_method_save_modified.
        APPEND | LOOP AT update-{ io_rap_bo_node->entityname } ASSIGNING FIELD-SYMBOL(<update_txt>).  | TO source_method_save_modified.
        APPEND |   INSERT VALUE #( | TO source_method_save_modified.

        LOOP AT key_fields INTO key_field.
          APPEND |         { key_field-name } = <update_txt>-{ key_field-cds_view_field }        |  TO source_method_save_modified.
        ENDLOOP.

        APPEND | ) INTO TABLE table_keys_txt.| TO source_method_save_modified.
        APPEND | ENDLOOP.| TO source_method_save_modified.
        APPEND | LOOP AT delete-{ io_rap_bo_node->entityname } ASSIGNING FIELD-SYMBOL(<delete_txt>).  | TO source_method_save_modified.
        APPEND |   INSERT VALUE #( | TO source_method_save_modified.

        LOOP AT key_fields INTO key_field.
          APPEND |         { key_field-name } = <delete_txt>-{ key_field-cds_view_field }        |  TO source_method_save_modified.
        ENDLOOP.

        APPEND | ) INTO TABLE table_keys_txt.| TO source_method_save_modified.
        APPEND | ENDLOOP.| TO source_method_save_modified.
        APPEND |  IF table_keys_txt IS NOT INITIAL.| TO source_method_save_modified.
        APPEND |   INSERT VALUE #( objname = '{ io_rap_bo_node->table_name }'  | TO source_method_save_modified.
        APPEND |                   tabkeys = REF #( table_keys_txt ) ) INTO TABLE object_Tables.| TO source_method_save_modified.
        APPEND | ENDIF.| TO source_method_save_modified.

        APPEND | CHECK object_tables IS NOT INITIAL.| TO source_method_save_modified.
        APPEND | TRY.| TO source_method_save_modified.
        APPEND |     cl_a4c_bc_factory=>get_handler( )->add_to_transport_request(| TO source_method_save_modified.
        APPEND |           EXPORTING| TO source_method_save_modified.
        APPEND |             iv_check_mode         = abap_false  | TO source_method_save_modified.
        APPEND |             it_object_tables      = object_tables| TO source_method_save_modified.
        APPEND |             iv_mandant_field_name = '{ io_rap_bo_node->field_name-client }'  | TO source_method_save_modified.
        APPEND |           IMPORTING| TO source_method_save_modified.
        APPEND |             rv_success            = DATA(success) ).| TO source_method_save_modified.
        APPEND |   CATCH cx_a4c_bc_exception.| TO source_method_save_modified.
        APPEND |     success = abap_false.| TO source_method_save_modified.
        APPEND | ENDTRY.| TO source_method_save_modified.
        APPEND | ASSERT success = 'S'. "point of no return - previous validation must catch all exceptions| TO source_method_save_modified.


        lo_saver->implementation->add_method(  method_save_modified  )->set_source( source_method_save_modified ).



      ENDIF.

    ENDIF.

**********************************************************************
** End of deletion 2020
**********************************************************************
  ENDMETHOD.


  METHOD create_condition.

    DATA lo_expression TYPE REF TO if_xco_ddl_expr_condition.

    LOOP AT it_condition_components INTO DATA(ls_condition_components).
      DATA(lo_projection_field) = xco_cp_ddl=>field( ls_condition_components-projection_field )->of_projection( ).
      DATA(lo_association_field) = xco_cp_ddl=>field( ls_condition_components-association_field )->of( CONV #( ls_condition_components-association_name ) ).

      DATA(lo_condition) = lo_projection_field->eq( lo_association_field ).

      IF lo_expression IS INITIAL.
        lo_expression = lo_condition.
      ELSE.
        lo_expression = lo_expression->and( lo_condition ).
      ENDIF.

      ro_expression = lo_expression.

    ENDLOOP.

  ENDMETHOD.


  METHOD create_control_structure.

    DATA lv_control_structure_name TYPE sxco_ad_object_name .
    lv_control_structure_name = to_upper( io_rap_bo_node->rap_node_objects-control_structure ).

    DATA(lo_specification) = mo_put_operation->for-tabl-for-structure->add_object(  lv_control_structure_name
     )->set_package( mo_package
     )->create_form_specification( ).

    "create a view entity
    lo_specification->set_short_description( |Control structure for { io_rap_bo_node->rap_node_objects-alias }| ).

    LOOP AT io_rap_bo_node->lt_fields  INTO  DATA(ls_header_fields) WHERE  key_indicator  <> abap_true .
      lo_specification->add_component( ls_header_fields-name
         )->set_type( xco_cp_abap_dictionary=>data_element( 'xsdboolean' ) ).
    ENDLOOP.

  ENDMETHOD.


  METHOD create_draft_table.

    DATA(lo_specification) = mo_draft_tabl_put_opertion->for-tabl-for-database_table->add_object(  io_rap_bo_node->draft_table_name
                                  )->set_package( mo_package
                                  )->create_form_specification( ).

    lo_specification->set_short_description( | Draft table for entity { io_rap_bo_node->rap_node_objects-cds_view_i } | ).

    DATA database_table_field  TYPE REF TO if_xco_gen_tabl_dbt_s_fo_field  .

    LOOP AT io_rap_bo_node->lt_fields INTO DATA(table_field_line).

      DATA(cds_field_name_upper) = to_upper( table_field_line-cds_view_field ).

      database_table_field = lo_specification->add_field( CONV #( cds_field_name_upper ) ).
      IF table_field_line-is_data_element = abap_true.
        database_table_field->set_type( xco_cp_abap_dictionary=>data_element( table_field_line-data_element ) ).
      ENDIF.
      IF table_field_line-is_built_in_type = abAP_TRUE.

        database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->for(
                                        iv_type     =  table_field_line-built_in_type
                                        iv_length   = table_field_line-built_in_type_length
                                        iv_decimals = table_field_line-built_in_type_decimals
                                        ) ).
      ENDIF.
      IF table_field_line-key_indicator = abap_true.
        database_table_field->set_key_indicator( ).
        "not_null must not be set for non-key fields of a draft table
        "this is because otherwise one would not be able to store data in the draft table
        "which is inconsistent and still being worked on
        "for non-key fields this is set like in the ADT quick fix that generates a draft table
        IF table_field_line-not_null = abap_true.
          database_table_field->set_not_null( ).
        ENDIF.
      ENDIF.

      IF table_field_line-currencycode IS NOT INITIAL.
        DATA(currkey_dbt_field_upper) = to_upper( table_field_line-currencycode ).
        "get the cds view field name of the currency or quantity filed
        DATA(cds_view_ref_field_name) = io_rap_bo_node->lt_fields[ name = currkey_dbt_field_upper ]-cds_view_field .
        database_table_field->currency_quantity->set_reference_table( CONV #( to_upper( io_rap_bo_node->draft_table_name ) ) )->set_reference_field( to_upper( cds_view_ref_field_name ) ).
      ENDIF.
      IF table_field_line-unitofmeasure IS NOT INITIAL.
        DATA(quantity_dbt_field_upper) = to_upper( table_field_line-unitofmeasure ).
        cds_view_ref_field_name = io_rap_bo_node->lt_fields[ name = quantity_dbt_field_upper ]-cds_view_field .
        database_table_field->currency_quantity->set_reference_table( CONV #( to_upper( io_rap_bo_node->draft_table_name ) ) )->set_reference_field( to_upper( cds_view_ref_field_name ) ).
      ENDIF.
    ENDLOOP.

**********************************************************************
** Begin of deletion 2020
**********************************************************************
    DATA(include_structure) = lo_specification->add_include( )->set_structure( iv_structure = CONV #( to_upper( 'sych_bdl_draft_admin_inc' ) )  )->set_group_name( to_upper( '%admin' )  ).
**********************************************************************
** End of deletion 2020
**********************************************************************


    "add additional fields if provided
    LOOP AT       io_rap_bo_node->lt_additional_fields INTO DATA(additional_fields) WHERE draft_table = abap_true.

      database_table_field = lo_specification->add_field( CONV #( to_upper( additional_fields-cds_view_field ) ) ).

      IF additional_fields-data_element IS NOT INITIAL.
        database_table_field->set_type( xco_cp_abap_dictionary=>data_element( to_upper( additional_fields-data_element ) ) ).
      ELSE.

        CASE  to_lower( additional_fields-built_in_type ).
          WHEN 'accp'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->accp ).
          WHEN 'clnt'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->clnt ).
          WHEN 'cuky'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->cuky ).
          WHEN 'dats'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->dats ).
          WHEN 'df16_raw'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->df16_raw ).
          WHEN 'df34_raw'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->df34_raw ).
          WHEN 'fltp'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->fltp ).
          WHEN 'int1'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->int1 ).
          WHEN 'int2'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->int2 ).
          WHEN 'int4'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->int4 ).
          WHEN 'int8'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->int8 ).
          WHEN 'lang'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->lang ).
          WHEN 'tims'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->tims ).
          WHEN 'char'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->char( additional_fields-built_in_type_length  ) ).
          WHEN 'curr'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->curr(
                                              iv_length   = additional_fields-built_in_type_length
                                              iv_decimals = additional_fields-built_in_type_decimals
                                            ) ).
          WHEN 'dec'  .
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->dec(
                                              iv_length   = additional_fields-built_in_type_length
                                              iv_decimals = additional_fields-built_in_type_decimals
                                            ) ).
          WHEN 'df16_dec'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->df16_dec(
                                              iv_length   = additional_fields-built_in_type_length
                                              iv_decimals = additional_fields-built_in_type_decimals
                                            ) ).
          WHEN 'df34_dec'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->df34_dec(
                                              iv_length   = additional_fields-built_in_type_length
                                              iv_decimals = additional_fields-built_in_type_decimals
                                            ) ).
          WHEN 'lchr' .
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->lchr( additional_fields-built_in_type_length  ) ).
          WHEN 'lraw'  .
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->lraw( additional_fields-built_in_type_length  ) ).
          WHEN 'numc'   .
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->numc( additional_fields-built_in_type_length  ) ).
          WHEN 'quan' .
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->quan(
                                              iv_length   = additional_fields-built_in_type_length
                                              iv_decimals = additional_fields-built_in_type_decimals
                                              ) ).
          WHEN 'raw'  .
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->raw( additional_fields-built_in_type_length  ) ).
          WHEN 'rawstring'.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->rawstring( additional_fields-built_in_type_length  ) ).
          WHEN 'sstring' .
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->sstring( additional_fields-built_in_type_length  ) ).
          WHEN 'string' .
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->string( additional_fields-built_in_type_length  ) ).
          WHEN 'unit'  .
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->unit( additional_fields-built_in_type_length  ) ).
          WHEN OTHERS.
            database_table_field->set_type( xco_cp_abap_dictionary=>built_in_type->for(
                                              iv_type     = to_upper( additional_fields-built_in_type )
                                              iv_length   = additional_fields-built_in_type_length
                                              iv_decimals = additional_fields-built_in_type_decimals
                                            ) ).
        ENDCASE.

      ENDIF.

    ENDLOOP.


  ENDMETHOD.


  METHOD create_i_cds_view.

    DATA ls_condition_components TYPE ts_condition_components.
    DATA lt_condition_components TYPE tt_condition_components.
    DATA lo_field TYPE REF TO if_xco_gen_ddls_s_fo_field .

    DATA(lo_specification) = mo_put_operation->for-ddls->add_object( io_rap_bo_node->rap_node_objects-cds_view_i
     )->set_package( mo_package
     )->create_form_specification( ).

    "create a view entity
    DATA(lo_view) = lo_specification->set_short_description( |CDS View for { io_rap_bo_node->rap_node_objects-alias  }|
      )->add_view_entity( ).

    "create a normal CDS view with DDIC view
    "maybe needed in order to generate code for a 1909 system
    "DATA(lo_view) = lo_specification->set_short_description( 'CDS View for ' &&  io_rap_bo_node->rap_node_objects-alias "mo_alias_header
    "   )->add_view( ).

    " Annotations.
    " lo_view->add_annotation( 'AbapCatalog' )->value->build( )->begin_record(
    "   )->add_member( 'sqlViewName' )->add_string( CONV #( io_rap_bo_node->rap_node_objects-ddic_view_i ) "mo_view_header )
    "   )->add_member( 'compiler.compareFilter' )->add_boolean( abap_true
    "   )->add_member( 'preserveKey' )->add_boolean( abap_true
    "   )->end_record( ).

    lo_view->add_annotation( 'AccessControl.authorizationCheck' )->value->build( )->add_enum( 'CHECK' ).
    lo_view->add_annotation( 'Metadata.allowExtensions' )->value->build( )->add_boolean( abap_true ).
    lo_view->add_annotation( 'EndUserText.label' )->value->build( )->add_string( 'CDS View for ' && io_rap_bo_node->rap_node_objects-alias ). " mo_alias_header ).

    IF io_rap_bo_node->is_root( ).
      lo_view->set_root( ).
    ELSE.

      CASE io_rap_bo_node->get_implementation_type(  ) .
        WHEN /dmo/cl_rap_node=>implementation_type-managed_uuid.

          DATA(parent_uuid_cds_field_name) = io_rap_bo_node->lt_fields[ name = io_rap_bo_node->field_name-parent_uuid ]-cds_view_field.
          DATA(uuid_cds_field_name_in_parent) = io_rap_bo_node->parent_node->lt_fields[ name = io_rap_bo_node->parent_node->field_name-uuid ]-cds_view_field.

          DATA(lo_condition) = xco_cp_ddl=>field( parent_uuid_cds_field_name )->of_projection( )->eq(
            xco_cp_ddl=>field( uuid_cds_field_name_in_parent )->of( '_' && io_rap_bo_node->parent_node->rap_node_objects-alias ) ).




        WHEN  /dmo/cl_rap_node=>implementation_type-unmanged_semantic OR /dmo/cl_rap_node=>implementation_type-managed_semantic.

          CLEAR ls_condition_components.
          CLEAR lt_condition_components.

          LOOP AT io_rap_bo_node->parent_node->semantic_key INTO DATA(ls_semantic_key).
            ls_condition_components-association_name = '_' && io_rap_bo_node->parent_node->rap_node_objects-alias.
            ls_condition_components-association_field = ls_semantic_key-cds_view_field.
            ls_condition_components-projection_field = ls_semantic_key-cds_view_field.
            APPEND ls_condition_components TO lt_condition_components.
          ENDLOOP.

          lo_condition = create_condition( lt_condition_components ).

      ENDCASE.

      "@todo - raise an exception when being initial
      IF lo_condition IS NOT INITIAL.

        lo_view->add_association( io_rap_bo_node->parent_node->rap_node_objects-cds_view_i )->set_to_parent(
    )->set_alias( '_' && io_rap_bo_node->parent_node->rap_node_objects-alias
    )->set_condition( lo_condition ).

      ENDIF.

      IF io_rap_bo_node->is_grand_child_or_deeper(  ).

        CASE io_rap_bo_node->get_implementation_type(  ) .
          WHEN /dmo/cl_rap_node=>implementation_type-managed_uuid.

            DATA(root_uuid_cds_field_name) = io_rap_bo_node->lt_fields[ name = io_rap_bo_node->field_name-root_uuid ]-cds_view_field.
            DATA(uuid_cds_field_name_in_root) = io_rap_bo_node->root_node->lt_fields[ name = io_rap_bo_node->root_node->field_name-uuid ]-cds_view_field.

            lo_condition = xco_cp_ddl=>field( root_uuid_cds_field_name )->of_projection( )->eq(
              xco_cp_ddl=>field( uuid_cds_field_name_in_root )->of( '_' && io_rap_bo_node->root_node->rap_node_objects-alias ) ).



          WHEN  /dmo/cl_rap_node=>implementation_type-unmanged_semantic OR /dmo/cl_rap_node=>implementation_type-managed_semantic.

            CLEAR ls_condition_components.
            CLEAR lt_condition_components.

            LOOP AT io_rap_bo_node->ROOT_node->semantic_key INTO DATA(ls_root_semantic_key).
              ls_condition_components-association_name = '_' && io_rap_bo_node->root_node->rap_node_objects-alias.
              ls_condition_components-association_field = ls_root_semantic_key-cds_view_field.
              ls_condition_components-projection_field = ls_root_semantic_key-cds_view_field.
              APPEND ls_condition_components TO lt_condition_components.
            ENDLOOP.

            lo_condition = create_condition( lt_condition_components ).

        ENDCASE.

        IF lo_condition IS NOT INITIAL.
          lo_view->add_association( io_rap_bo_node->root_node->rap_node_objects-cds_view_i
            )->set_alias( '_' && io_rap_bo_node->root_node->rap_node_objects-alias
            )->set_cardinality(  xco_cp_cds=>cardinality->one
            )->set_condition( lo_condition ).
        ENDIF.

      ENDIF.

    ENDIF.

    " Data source.
    CASE io_rap_bo_node->data_source_type.
      WHEN io_rap_bo_node->data_source_types-table.
        lo_view->data_source->set_view_entity( CONV #( io_rap_bo_node->table_name ) ).
      WHEN io_rap_bo_node->data_source_types-cds_view.
        lo_view->data_source->set_view_entity( CONV #( io_rap_bo_node->cds_view_name ) ).
    ENDCASE.

    IF io_rap_bo_node->is_virtual_root(  ) = abap_true.
      "add the following statement
      "left outer join zcarrier_002 as carr on 0 = 0
      "   data(left_outer_join) = lo_view->data_source->add_left_outer_join( io_data_source = io_rap_bo_node->childnodes[ 1 ]->data_source_name ).

      " Association.
      DATA(condition) = xco_cp_ddl=>field( '0' )->eq( xco_cp_ddl=>field( '0' ) ).
      "DATA(cardinality) = xco_cp_cds=>cardinality->range( iv_min = 1 iv_max = 1 ).

      DATA mo_data_source  TYPE REF TO if_xco_ddl_expr_data_source  .
      "mo_data_source = .

      DATA(left_outer_join) = lo_view->data_source->add_left_outer_join( xco_cp_ddl=>data_source->database_table( CONV #( root_node->childnodes[ 1 ]->data_source_name ) )->set_alias( CONV #( root_node->singleton_child_tab_name ) ) ).

      "@todo - add code after HFC2 2008 has been applied
      "left_outer_join->set_condition( condition ).

      lo_view->set_where( xco_cp_ddl=>field( 'I_Language.Language' )->eq( xco_cp_ddl=>expression->for( '$session.system_language' ) ) ).

    ENDIF.

    IF io_rap_bo_node->has_childs(  ).   " create_item_objects(  ).
      " Composition.

      "change to a new property "childnodes" which only contains the direct childs
      LOOP AT io_rap_bo_node->childnodes INTO DATA(lo_childnode).

        lo_view->add_composition( lo_childnode->rap_node_objects-cds_view_i "  mo_i_cds_item
          )->set_cardinality( xco_cp_cds=>cardinality->zero_to_n
          )->set_alias( '_' && lo_childnode->rap_node_objects-alias ). " mo_alias_item ).

      ENDLOOP.

    ENDIF.

    "Client field does not need to be specified in client-specific CDS view
    LOOP AT io_rap_bo_node->lt_fields  INTO  DATA(ls_header_fields) WHERE  name  <> io_rap_bo_node->field_name-client . "   co_client.

      IF ls_header_fields-key_indicator = abap_true.
        lo_field = lo_view->add_field( xco_cp_ddl=>field( ls_header_fields-name )
           )->set_key( )->set_alias(  ls_header_fields-cds_view_field  ).
      ELSE.
        lo_field = lo_view->add_field( xco_cp_ddl=>field( ls_header_fields-name )
           )->set_alias( ls_header_fields-cds_view_field ).
      ENDIF.

      "add @Semantics annotation for currency code
      IF ls_header_fields-currencycode IS NOT INITIAL.
        READ TABLE io_rap_bo_node->lt_fields INTO DATA(ls_field) WITH KEY name = to_upper( ls_header_fields-currencycode ).
        IF sy-subrc = 0.
          "for example @Semantics.amount.currencyCode: 'CurrencyCode'
          lo_field->add_annotation( 'Semantics.amount.currencyCode' )->value->build( )->add_string( CONV #( ls_field-cds_view_field ) ).
        ENDIF.
      ENDIF.

      "add @Semantics annotation for unit of measure
      IF ls_header_fields-unitofmeasure IS NOT INITIAL.
        CLEAR ls_field.
        READ TABLE io_rap_bo_node->lt_fields INTO ls_field WITH KEY name = to_upper( ls_header_fields-unitofmeasure ).
        IF sy-subrc = 0.
          "for example @Semantics.quantity.unitOfMeasure: 'QuantityUnit'
          lo_field->add_annotation( 'Semantics.quantity.unitOfMeasure' )->value->build( )->add_string( CONV #( ls_field-cds_view_field ) ).
        ENDIF.
      ENDIF.

      CASE ls_header_fields-name.
        WHEN io_rap_bo_node->field_name-created_at.
          lo_field->add_annotation( 'Semantics.systemDateTime.createdAt' )->value->build( )->add_boolean( abap_true ).
        WHEN io_rap_bo_node->field_name-created_by.
          lo_field->add_annotation( 'Semantics.user.createdBy' )->value->build( )->add_boolean( abap_true ).
        WHEN io_rap_bo_node->field_name-last_changed_at.
          lo_field->add_annotation( 'Semantics.systemDateTime.lastChangedAt' )->value->build( )->add_boolean( abap_true ).
        WHEN io_rap_bo_node->field_name-last_changed_by.
          lo_field->add_annotation( 'Semantics.user.lastChangedBy' )->value->build( )->add_boolean( abap_true ).
        WHEN io_rap_bo_node->field_name-local_instance_last_changed_at.
          lo_field->add_annotation( 'Semantics.systemDateTime.localInstanceLastChangedAt' )->value->build( )->add_boolean( abap_true ).
        WHEN io_rap_bo_node->field_name-local_instance_last_changed_by.
          lo_field->add_annotation( 'Semantics.user.localInstanceLastChangedBy' )->value->build( )->add_boolean( abap_true ).
      ENDCASE.

    ENDLOOP.

    "IF create_item_objects(  ).
    IF io_rap_bo_node->has_childs(  ).

      "change to a new property "childnodes" which only contains the direct childs
      LOOP AT io_rap_bo_node->childnodes INTO lo_childnode.

        "publish association to item  view
        lo_view->add_field( xco_cp_ddl=>field( '_' && lo_childnode->rap_node_objects-alias ) ).

      ENDLOOP.

    ENDIF.

    IF io_rap_bo_node->is_root(  ) = abap_false.
      "publish association to parent
      lo_view->add_field( xco_cp_ddl=>field( '_' && io_rap_bo_node->parent_node->rap_node_objects-alias ) ).
    ENDIF.

    IF io_rap_bo_node->is_grand_child_or_deeper(  ).
      "add assocation to root node
      lo_view->add_field( xco_cp_ddl=>field( '_' && io_rap_bo_node->root_node->rap_node_objects-alias ) ).
    ENDIF.

    "add associations

    LOOP AT io_rap_bo_node->lt_association INTO DATA(ls_assocation).

      CLEAR ls_condition_components.
      CLEAR lt_condition_components.
      LOOP AT ls_assocation-condition_components INTO DATA(ls_components).
        ls_condition_components-association_field =  ls_components-association_field.
        ls_condition_components-projection_field = ls_components-projection_field.
        ls_condition_components-association_name = ls_assocation-name.
        APPEND ls_condition_components TO lt_condition_components.
      ENDLOOP.

      lo_condition = create_condition( lt_condition_components ).

      DATA(lo_association) = lo_view->add_association( ls_assocation-target )->set_alias(
           ls_assocation-name
          )->set_condition( lo_condition ).

      CASE ls_assocation-cardinality .
        WHEN /dmo/cl_rap_node=>cardinality-one.
          lo_association->set_cardinality(  xco_cp_cds=>cardinality->one ).
        WHEN /dmo/cl_rap_node=>cardinality-one_to_n.
          lo_association->set_cardinality(  xco_cp_cds=>cardinality->one_to_n ).
        WHEN /dmo/cl_rap_node=>cardinality-zero_to_n.
          lo_association->set_cardinality(  xco_cp_cds=>cardinality->zero_to_n ).
        WHEN /dmo/cl_rap_node=>cardinality-zero_to_one.
          lo_association->set_cardinality(  xco_cp_cds=>cardinality->zero_to_one ).
        WHEN /dmo/cl_rap_node=>cardinality-one_to_one.
          "@todo: currently association[1] will be generated
          "fix available with 2008 HFC2
          lo_association->set_cardinality(  xco_cp_cds=>cardinality->range( iv_min = 1 iv_max = 1 ) ).
      ENDCASE.

      "publish association
      lo_view->add_field( xco_cp_ddl=>field( ls_assocation-name ) ).

    ENDLOOP.

    LOOP AT       io_rap_bo_node->lt_additional_fields INTO DATA(additional_fields) WHERE cds_interface_view = abap_true.

      lo_field = lo_view->add_field( xco_cp_ddl=>expression->for( additional_fields-name )  ).
      IF additional_fields-cds_view_field IS NOT INITIAL.
        lo_Field->set_alias( additional_fields-cds_view_field ).
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


  METHOD create_mde_view.
    DATA pos TYPE i VALUE 0.
    DATA lo_field TYPE REF TO if_xco_gen_ddlx_s_fo_field .

    DATA(lo_specification) = mo_put_operation->for-ddlx->add_object(  io_rap_bo_node->rap_node_objects-meta_data_extension " cds_view_p " mo_p_cds_header
      )->set_package( mo_package
      )->create_form_specification( ).

    lo_specification->set_short_description( |MDE for { io_rap_bo_node->rap_node_objects-alias }|
      )->set_layer( xco_cp_metadata_extension=>layer->customer
      )->set_view( io_rap_bo_node->rap_node_objects-cds_view_p ). " cds_view_p ).

    "begin_array --> square bracket open
    "Begin_record-> curly bracket open


    lo_specification->add_annotation( 'UI' )->value->build(
    )->begin_record(
        )->add_member( 'headerInfo'
         )->begin_record(
          )->add_member( 'typeName' )->add_string( io_rap_bo_node->rap_node_objects-alias && ''
          )->add_member( 'typeNamePlural' )->add_string( io_rap_bo_node->rap_node_objects-alias && 's'
          )->add_member( 'title'
            )->begin_record(
              )->add_member( 'type' )->add_enum( 'STANDARD'
              )->add_member( 'label' )->add_string( io_rap_bo_node->rap_node_objects-alias && ''
              "@todo: Check what happens if several key fields are present
              "for a first test we just take the first one.
              "also check what happens if no semantic key has been specified
              )->add_member( 'value' )->add_string( io_rap_bo_node->object_id_cds_field_name && '' "semantic_keys[ 1 ]  && '' " mo_header_semantic_key && ''
        )->end_record(
        )->end_record(
      )->end_record(
    ).



    "Client field does not need to be specified in client-specific CDS view
    LOOP AT io_rap_bo_node->lt_fields INTO  DATA(ls_header_fields) WHERE name <> io_rap_bo_node->field_name-client.

      pos += 10.

      lo_field = lo_specification->add_field( ls_header_fields-cds_view_field ).


      "todo: create methods that can be reused for custom entities
      "add_root_facet_has_childs( lo_field )
      "add_root_facet_has_no_childs( lo_field )
      "add_child_facet_has_childs( lo_field )
      "add_child_facet_has_no_childs(lo_field)
      "hide_field(lo_field)
      "add_lineitem_annoation(lo_field)
      "add_identification_annoation(lo_field)
      "add_select_option_annotation(lo_field)

      "put facet annotation in front of the first
      IF pos = 10.
        IF io_rap_bo_node->is_virtual_root(  ) = abap_true.

          lo_field->add_annotation( 'UI.facet' )->value->build(
            )->begin_array(
*                  )->begin_record(
*                    )->add_member( 'id' )->add_string( 'idCollection'
*                    )->add_member( 'type' )->add_enum( 'COLLECTION'
*                    )->add_member( 'label' )->add_string( io_rap_bo_node->rap_node_objects-alias && ''
*                    )->add_member( 'position' )->add_number( 10
*                  )->end_record(
              )->begin_record(
                )->add_member( 'id' )->add_string( 'idIdentification'
                )->add_member( 'parentId' )->add_string( 'idCollection'
                )->add_member( 'type' )->add_enum( 'IDENTIFICATION_REFERENCE'
                )->add_member( 'label' )->add_string( 'General Information'
                )->add_member( 'position' )->add_number( 10
                )->add_member( 'hidden' )->add_boolean( abap_true
              )->end_record(
              "@todo check what happens if an entity has several child entities
              )->begin_record(
                )->add_member( 'purpose' )->add_enum( 'STANDARD'
                )->add_member( 'type' )->add_enum( 'LINEITEM_REFERENCE'
                )->add_member( 'label' )->add_string( io_rap_bo_node->childnodes[ 1 ]->rap_node_objects-alias && ''
                )->add_member( 'position' )->add_number( 20
                )->add_member( 'targetElement' )->add_string( '_' && io_rap_bo_node->childnodes[ 1 ]->rap_node_objects-alias

              )->end_record(
            )->end_array( ).

        ELSE.

          IF io_rap_bo_node->is_root(  ) = abap_true.

            IF io_rap_bo_node->has_childs(  ).

              lo_field->add_annotation( 'UI.facet' )->value->build(
                )->begin_array(
                  )->begin_record(
                    )->add_member( 'id' )->add_string( 'idCollection'
                    )->add_member( 'type' )->add_enum( 'COLLECTION'
                    )->add_member( 'label' )->add_string( io_rap_bo_node->rap_node_objects-alias && ''
                    )->add_member( 'position' )->add_number( 10
                  )->end_record(
                  )->begin_record(
                    )->add_member( 'id' )->add_string( 'idIdentification'
                    )->add_member( 'parentId' )->add_string( 'idCollection'
                    )->add_member( 'type' )->add_enum( 'IDENTIFICATION_REFERENCE'
                    )->add_member( 'label' )->add_string( 'General Information'
                    )->add_member( 'position' )->add_number( 10
                  )->end_record(
                  "@todo check what happens if an entity has several child entities
                  )->begin_record(
                    )->add_member( 'id' )->add_string( 'idLineitem'
                    )->add_member( 'type' )->add_enum( 'LINEITEM_REFERENCE'
                    )->add_member( 'label' )->add_string( io_rap_bo_node->childnodes[ 1 ]->rap_node_objects-alias && ''
                    )->add_member( 'position' )->add_number( 20
                    )->add_member( 'targetElement' )->add_string( '_' && io_rap_bo_node->childnodes[ 1 ]->rap_node_objects-alias
                  )->end_record(
                )->end_array( ).
            ELSE.

              lo_field->add_annotation( 'UI.facet' )->value->build(
                )->begin_array(
                  )->begin_record(
                    )->add_member( 'id' )->add_string( 'idCollection'
                    )->add_member( 'type' )->add_enum( 'COLLECTION'
                    )->add_member( 'label' )->add_string( io_rap_bo_node->rap_node_objects-alias && ''
                    )->add_member( 'position' )->add_number( 10
                  )->end_record(
                  )->begin_record(
                    )->add_member( 'id' )->add_string( 'idIdentification'
                    )->add_member( 'parentId' )->add_string( 'idCollection'
                    )->add_member( 'type' )->add_enum( 'IDENTIFICATION_REFERENCE'
                    )->add_member( 'label' )->add_string( 'General Information'
                    )->add_member( 'position' )->add_number( 10
                  )->end_record(
                )->end_array( ).

            ENDIF.

          ELSE.

            IF io_rap_bo_node->has_childs(  ).

              lo_field->add_annotation( 'UI.facet' )->value->build(
                )->begin_array(
                  )->begin_record(
                    )->add_member( 'id' )->add_string( CONV #( 'id' && io_rap_bo_node->rap_node_objects-alias )
                    )->add_member( 'purpose' )->add_enum( 'STANDARD'
                    )->add_member( 'type' )->add_enum( 'IDENTIFICATION_REFERENCE'
                    )->add_member( 'label' )->add_string( CONV #( io_rap_bo_node->rap_node_objects-alias )
                    )->add_member( 'position' )->add_number( 10
                  )->end_record(
                  )->begin_record(
                      )->add_member( 'id' )->add_string( 'idLineitem'
                      )->add_member( 'type' )->add_enum( 'LINEITEM_REFERENCE'
                      )->add_member( 'label' )->add_string( io_rap_bo_node->childnodes[ 1 ]->rap_node_objects-alias && ''
                      )->add_member( 'position' )->add_number( 20
                      )->add_member( 'targetElement' )->add_string( '_' && io_rap_bo_node->childnodes[ 1 ]->rap_node_objects-alias
                    )->end_record(
                )->end_array( ).

            ELSE.

              lo_field->add_annotation( 'UI.facet' )->value->build(
                )->begin_array(
                  )->begin_record(
                    )->add_member( 'id' )->add_string( CONV #( 'id' && io_rap_bo_node->rap_node_objects-alias )
                    )->add_member( 'purpose' )->add_enum( 'STANDARD'
                    )->add_member( 'type' )->add_enum( 'IDENTIFICATION_REFERENCE'
                    )->add_member( 'label' )->add_string( CONV #( io_rap_bo_node->rap_node_objects-alias )
                    )->add_member( 'position' )->add_number( 10
                  )->end_record(
                )->end_array( ).

            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.


      IF ls_header_fields-is_hidden = abap_true.

        lo_field->add_annotation( 'UI.hidden' )->value->build(  )->add_boolean( iv_value =  abap_true ).

      ELSE.

        DATA(lo_valuebuilder) = lo_field->add_annotation( 'UI.lineItem' )->value->build( ).

        DATA(lo_record) = lo_valuebuilder->begin_array(
        )->begin_record(
            )->add_member( 'position' )->add_number( pos
            )->add_member( 'importance' )->add_enum( 'HIGH').
        "if field is based on a data element label will be set from its field description
        "if its a built in type we will set a label whith a meaningful default vaule that
        "can be changed by the developer afterwards
        IF ls_header_fields-is_data_element = abap_false.
          lo_record->add_member( 'label' )->add_string( CONV #( ls_header_fields-cds_view_field ) ).
        ENDIF.
        lo_valuebuilder->end_record( )->end_array( ).

        lo_valuebuilder = lo_field->add_annotation( 'UI.identification' )->value->build( ).
        lo_record = lo_valuebuilder->begin_array(
        )->begin_record(
            )->add_member( 'position' )->add_number( pos ).
        IF ls_header_fields-is_data_element = abap_false.
          lo_record->add_member( 'label' )->add_string( CONV #( ls_header_fields-cds_view_field ) ).
        ENDIF.
        lo_valuebuilder->end_record( )->end_array( ).

        "add selection fields for semantic key fields or for the fields that are marked as object id

        IF io_rap_bo_node->is_root(  ) = abap_true AND
           ( io_rap_bo_node->get_implementation_type( ) = io_rap_bo_node->implementation_type-unmanged_semantic OR
              io_rap_bo_node->get_implementation_type( ) = io_rap_bo_node->implementation_type-managed_semantic ) AND
              ls_header_fields-key_indicator = abap_true.

          lo_field->add_annotation( 'UI.selectionField' )->value->build(
          )->begin_array(
          )->begin_record(
              )->add_member( 'position' )->add_number( pos
            )->end_record(
          )->end_array( ).

        ENDIF.

        IF io_rap_bo_node->is_root(  ) = abap_true AND
           io_rap_bo_node->get_implementation_type( ) = io_rap_bo_node->implementation_type-managed_uuid  AND
           ls_header_fields-name = io_rap_bo_node->object_id.

          lo_field->add_annotation( 'UI.selectionField' )->value->build(
          )->begin_array(
          )->begin_record(
              )->add_member( 'position' )->add_number( pos
            )->end_record(
          )->end_array( ).

        ENDIF.



      ENDIF.

    ENDLOOP.
  ENDMETHOD.


  METHOD create_p_cds_view.

    DATA fuzzinessThreshold TYPE p LENGTH 3 DECIMALS 2.
    fuzzinessthreshold = 9 / 10.

    DATA(lo_specification) = mo_put_operation->for-ddls->add_object( io_rap_bo_node->rap_node_objects-cds_view_p
     )->set_package( mo_package
     )->create_form_specification( ).

    DATA(lo_view) = lo_specification->set_short_description( |Projection View for { io_rap_bo_node->rap_node_objects-alias }|
      )->add_projection_view( ).

    " Annotations.
    lo_view->add_annotation( 'AccessControl.authorizationCheck' )->value->build( )->add_enum( 'CHECK' ).
    lo_view->add_annotation( 'Metadata.allowExtensions' )->value->build( )->add_boolean( abap_true ).
    lo_view->add_annotation( 'EndUserText.label' )->value->build( )->add_string( 'Projection View for ' && io_rap_bo_node->rap_node_objects-alias ).

    "@ObjectModel.semanticKey: ['HolidayAllID']

    DATA(semantic_key) = lo_view->add_annotation( 'ObjectModel.semanticKey' )->value->build( )->begin_array(  ).
    semantic_key->add_string( CONV #( io_rap_bo_node->object_id_cds_field_name ) ).
    semantic_key->end_array(  ).

    lo_view->add_annotation( 'Search.searchable' )->value->build( )->add_boolean( abap_true ).


    IF io_rap_bo_node->is_root( ).
      lo_view->set_root( ).
    ENDIF.

    " Data source.
    lo_view->data_source->set_view_entity( iv_view_entity = io_rap_bo_node->rap_node_objects-cds_view_i ).


    "Client field does not need to be specified in client-specific CDS view
    LOOP AT io_rap_bo_node->lt_fields INTO  DATA(ls_header_fields) WHERE name  <> io_rap_bo_node->field_name-client.

      DATA(lo_field) = lo_view->add_field( xco_cp_ddl=>field(  ls_header_fields-cds_view_field   )
         ). "->set_alias(  ls_header_fields-cds_view_field   ).

      IF ls_header_fields-key_indicator = abap_true  .
        lo_field->set_key(  ).
        IF io_rap_bo_node->get_implementation_type( ) = io_rap_bo_node->implementation_type-managed_semantic OR
           io_rap_bo_node->get_implementation_type( ) = io_rap_bo_node->implementation_type-unmanged_semantic.
          lo_field->add_annotation( 'Search.defaultSearchElement' )->value->build( )->add_boolean( abap_true ).
          lo_field->add_annotation( 'Search.fuzzinessThreshold' )->value->build( )->add_number( iv_value = fuzzinessThreshold ).
        ENDIF.
      ENDIF.

      CASE ls_header_fields-name.
        WHEN io_rap_bo_node->object_id.
          IF ls_header_fields-key_indicator = abap_false.
            lo_field->add_annotation( 'Search.defaultSearchElement' )->value->build( )->add_boolean( abap_true ).
            lo_field->add_annotation( 'Search.fuzzinessThreshold' )->value->build( )->add_number( iv_value = fuzzinessThreshold ).
          ENDIF.
      ENDCASE.

      "add @Semantics annotation once available
      IF ls_header_fields-currencycode IS NOT INITIAL.
        READ TABLE io_rap_bo_node->lt_fields INTO DATA(ls_field) WITH KEY name = ls_header_fields-currencycode.
        IF sy-subrc = 0.
          lo_field->add_annotation( 'Semantics.amount.currencyCode' )->value->build( )->add_string( CONV #( ls_field-cds_view_field ) ).
        ENDIF.
      ENDIF.

      "add @Semantics annotation for unit of measure
      IF ls_header_fields-unitofmeasure IS NOT INITIAL.
        CLEAR ls_field.
        READ TABLE io_rap_bo_node->lt_fields INTO ls_field WITH KEY name = to_upper( ls_header_fields-unitofmeasure ).
        IF sy-subrc = 0.
          "for example @Semantics.quantity.unitOfMeasure: 'QuantityUnit'
          lo_field->add_annotation( 'Semantics.quantity.unitOfMeasure' )->value->build( )->add_string( CONV #( ls_field-cds_view_field ) ).
        ENDIF.
      ENDIF.

      "has to be set in 2102
      "can be omitted later
      IF ls_header_fields-is_unitofmeasure = abap_true.
        lo_field->add_annotation( 'Semantics.unitOfMeasure' )->value->build( )->add_boolean( abap_true ).
      ENDIF.

      IF ls_header_fields-has_valuehelp = abap_true.

        READ TABLE io_rap_bo_node->lt_valuehelp INTO DATA(ls_valuehelp) WITH KEY localelement = ls_header_fields-cds_view_field.

        IF sy-subrc = 0.

          DATA(lo_valuebuilder) = lo_field->add_annotation( 'Consumption.valueHelpDefinition' )->value->build( ).

          lo_valuebuilder->begin_array(
                     )->begin_record(
                       )->add_member( 'entity'
                          )->begin_record(
                             )->add_member( 'name' )->add_string( CONV #( ls_valuehelp-name )
                             )->add_member( 'element' )->add_string( CONV #( ls_valuehelp-element )
                          )->end_record( ).

          IF ls_valuehelp-additionalbinding IS NOT INITIAL.

            lo_valuebuilder->add_member( 'additionalBinding'
            )->begin_array( ).

            LOOP AT ls_valuehelp-additionalbinding INTO DATA(ls_additionalbinding).

              DATA(lo_record) = lo_valuebuilder->begin_record(
                )->add_member( 'localElement' )->add_string( CONV #( ls_additionalbinding-localelement )
                )->add_member( 'element' )->add_string( CONV #( ls_additionalbinding-element )
                ).
              IF ls_additionalbinding-usage IS NOT INITIAL.
                lo_record->add_member( 'usage' )->add_enum( CONV #( ls_additionalbinding-usage ) ).
              ENDIF.

              lo_valuebuilder->end_record(  ).

            ENDLOOP.

            lo_valuebuilder->end_array( ).

          ENDIF.

          lo_valuebuilder->end_record( )->end_array( ).

        ENDIF.

      ENDIF.



    ENDLOOP.

    IF io_rap_bo_node->has_childs(  ).   " create_item_objects(  ).
      " Composition.

      "change to a new property "childnodes" which only contains the direct childs
      LOOP AT io_rap_bo_node->childnodes INTO DATA(lo_childnode).

        lo_view->add_field( xco_cp_ddl=>field( '_' && lo_childnode->rap_node_objects-alias ) )->set_redirected_to_compos_child( lo_childnode->rap_node_objects-cds_view_p ).


      ENDLOOP.

    ENDIF.

    IF io_rap_bo_node->is_root(  ) = abap_false.
      " "publish association to parent
      lo_view->add_field( xco_cp_ddl=>field( '_' && io_rap_bo_node->parent_node->rap_node_objects-alias ) )->set_redirected_to_parent( io_rap_bo_node->parent_node->rap_node_objects-cds_view_p ).
    ENDIF.

    "for grand-child nodes we have to add an association to the root node
    IF io_rap_bo_node->is_grand_child_or_deeper(  ).
      lo_view->add_field( xco_cp_ddl=>field( '_' && io_rap_bo_node->root_node->rap_node_objects-alias ) )->set_redirected_to( io_rap_bo_node->root_node->rap_node_objects-cds_view_p ).
    ENDIF.


    "publish associations

    LOOP AT io_rap_bo_node->lt_association INTO DATA(ls_assocation).
      lo_view->add_field( xco_cp_ddl=>field( ls_assocation-name ) ).
    ENDLOOP.


    LOOP AT       io_rap_bo_node->lt_additional_fields INTO DATA(additional_fields) WHERE cds_projection_view = abap_true.

      lo_field = lo_view->add_field( xco_cp_ddl=>expression->for( CONV #( additional_fields-cds_view_field ) )  ).

      IF additional_fields-localized = abap_true.
        lo_Field->set_localized( abap_true ).
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


  METHOD create_service_binding.
**********************************************************************
** Begin of deletion 2020
**********************************************************************
    DATA lv_service_binding_name TYPE sxco_srvb_object_name.
    lv_service_binding_name = to_upper( io_rap_bo_node->root_node->rap_root_node_objects-service_binding ).

    DATA lv_service_definition_name TYPE sxco_srvd_object_name.
    lv_service_definition_name = to_upper( io_rap_bo_node->root_node->rap_root_node_objects-service_definition ).

    DATA(lo_specification_header) = mo_srvb_put_operation->for-srvb->add_object(   lv_service_binding_name
                                    )->set_package( mo_package
                                    )->create_form_specification( ).

    lo_specification_header->set_short_description( |Service binding for { io_rap_bo_node->root_node->entityname }| ).


    CASE io_rap_bo_node->root_node->binding_type.
      WHEN io_rap_bo_node->binding_type_name-odata_v4_ui.
        lo_specification_header->set_binding_type( xco_cp_service_binding=>binding_type->odata_v4_ui ).
      WHEN io_rap_bo_node->binding_type_name-odata_v2_ui.
        lo_specification_header->set_binding_type( xco_cp_service_binding=>binding_type->odata_v2_ui ).
      WHEN io_rap_bo_node->binding_type_name-odata_v4_web_api.
        lo_specification_header->set_binding_type( xco_cp_service_binding=>binding_type->odata_v4_web_api ).
      WHEN io_rap_bo_node->binding_type_name-odata_v2_web_api..
        lo_specification_header->set_binding_type( xco_cp_service_binding=>binding_type->odata_v2_web_api ).
      WHEN OTHERS.
        RAISE EXCEPTION TYPE /dmo/cx_rap_generator
          EXPORTING
            textid     = /dmo/cx_rap_generator=>invalid_binding_type
            mv_value   = io_rap_bo_node->root_node->binding_type
            mv_value_2 = io_rap_bo_node->supported_binding_types.
    ENDCASE.


    lo_specification_header->add_service( )->add_version( '0001' )->set_service_definition( lv_service_definition_name ).


**********************************************************************
** End of deletion 2020
**********************************************************************
  ENDMETHOD.


  METHOD create_service_definition.


    TYPES: BEGIN OF ty_cds_views_used_by_assoc,
             name   TYPE /dmo/cl_rap_node=>ts_assocation-name,    "    sxco_ddef_alias_name,
             target TYPE /dmo/cl_rap_node=>ts_assocation-target,
           END OF ty_cds_views_used_by_assoc.
    DATA  lt_cds_views_used_by_assoc  TYPE STANDARD TABLE OF ty_cds_views_used_by_assoc.
    DATA  ls_cds_views_used_by_assoc  TYPE ty_cds_views_used_by_assoc.

    DATA(lo_specification_header) = mo_put_operation->for-srvd->add_object(  io_rap_bo_node->rap_root_node_objects-service_definition
                                    )->set_package( mo_package
                                    )->create_form_specification( ).

    lo_specification_header->set_short_description( |Service definition for { io_rap_bo_node->root_node->entityname }|  ).

    "add exposure for root node
    CASE root_node->data_source_type.
      WHEN root_node->data_source_types-table OR root_node->data_source_types-cds_view.
        lo_specification_header->add_exposure( root_node->rap_node_objects-cds_view_p )->set_alias( root_node->rap_node_objects-alias ).
      WHEN root_node->data_source_types-structure OR root_node->data_source_types-abap_type.
        lo_specification_header->add_exposure( root_node->rap_node_objects-cds_view_i )->set_alias( root_node->rap_node_objects-alias ).
    ENDCASE.
    "add exposure for all child nodes
    LOOP AT root_node->all_childnodes INTO DATA(lo_childnode).
      "add all nodes to the service definition
      CASE lo_childnode->data_source_type.
        WHEN lo_childnode->data_source_types-table OR lo_childnode->data_source_types-cds_view.
          lo_specification_header->add_exposure( lo_childnode->rap_node_objects-cds_view_p )->set_alias( lo_childnode->rap_node_objects-alias ).
        WHEN lo_childnode->data_source_types-abap_type OR lo_childnode->data_source_types-structure.
          lo_specification_header->add_exposure( lo_childnode->rap_node_objects-cds_view_i )->set_alias( lo_childnode->rap_node_objects-alias ).
      ENDCASE.

      "create a list of all CDS views used in associations to the service definition
      LOOP AT lo_childnode->lt_association INTO DATA(ls_assocation).
        "remove the first character which is an underscore
        ls_cds_views_used_by_assoc-name = substring( val = ls_assocation-name off = 1 ).
        ls_cds_views_used_by_assoc-target =  ls_assocation-target.
        COLLECT ls_cds_views_used_by_assoc INTO lt_cds_views_used_by_assoc.
      ENDLOOP.
      LOOP AT lo_childnode->lt_valuehelp INTO DATA(ls_valuehelp).
        ls_cds_views_used_by_assoc-name = ls_valuehelp-alias.
        ls_cds_views_used_by_assoc-target = ls_valuehelp-name.
        COLLECT ls_cds_views_used_by_assoc INTO lt_cds_views_used_by_assoc.
      ENDLOOP.
    ENDLOOP.

    "add exposure for all associations and value helps that have been collected (and condensed) in the step before
    LOOP AT lt_cds_views_used_by_assoc INTO ls_cds_views_used_by_assoc.
      lo_specification_header->add_exposure( ls_cds_views_used_by_assoc-target )->set_alias( ls_cds_views_used_by_assoc-name ).
    ENDLOOP.


  ENDMETHOD.


  METHOD generate_bo.


    IF root_node->multi_edit = abap_true.
*      DATA(root_node_with_virtual) = root_node->add_virtual_root_node( ).
*      root_node = root_node_with_virtual.
      root_node = root_node->add_virtual_root_node( ).
    ENDIF.
    assign_package( ).

    " on premise create draft tables first
    " uses mo_draft_tabl_put_opertion

    IF root_node->draft_enabled = abap_true.

      create_draft_table(
      EXPORTING
                      io_rap_bo_node   = root_node
                  ).

      LOOP AT root_node->all_childnodes INTO DATA(lo_child_node).

        create_draft_table(
        EXPORTING
                        io_rap_bo_node   = lo_child_node
                    ).

      ENDLOOP.

      IF root_node->skip_activation = abap_true.
**********************************************************************
** Begin of deletion 2020
**********************************************************************
        DATA(lo_result) = mo_draft_tabl_put_opertion->execute( VALUE #( ( xco_cp_generation=>put_operation_option->skip_activation ) ) ).
**********************************************************************
** End of deletion 2020
**********************************************************************
**********************************************************************
** Begin of insertion 2020
**********************************************************************
*        DATA(lo_result) = mo_draft_tabl_put_opertion->execute(  ).
**********************************************************************
** End of insertion 2020
**********************************************************************
      ELSE.
        lo_result = mo_draft_tabl_put_opertion->execute(  ).
      ENDIF.

      DATA(lo_findings) = lo_result->findings.
      DATA(lt_findings) = lo_findings->get( ).

      "add draft structures
      "only needed for on premise systems with older release
      "method is not implemented for xco cloud api

**********************************************************************
** Begin of insertion 2020
**********************************************************************
      xco_api->add_draft_include( root_node->draft_table_name  ).
      LOOP AT root_node->all_childnodes INTO lo_child_node.
        xco_api->add_draft_include( lo_child_node->draft_table_name  ).
      ENDLOOP.
**********************************************************************
** End of insertion 2020
**********************************************************************


    ENDIF.

    CASE root_node->data_source_type.

      WHEN root_node->data_source_types-abap_type OR root_node->data_source_types-structure.

        create_custom_entity(
              EXPORTING
                io_rap_bo_node   = root_node
            ).

        create_custom_query(
              EXPORTING
                io_rap_bo_node   = root_node
            ).

      WHEN OTHERS.

        create_i_cds_view(
          EXPORTING
            io_rap_bo_node   = root_node
        ).

        create_p_cds_view(
          EXPORTING
            io_rap_bo_node   = root_node
        ).

        create_mde_view(
              EXPORTING
                io_rap_bo_node   = root_node
            ).

    ENDCASE.

    IF root_node->transactional_behavior = abap_true.




      create_bdef(
        EXPORTING
                    io_rap_bo_node   = root_node
                ). "

      CASE root_node->data_source_type.

        WHEN root_node->data_source_types-table OR root_node->data_source_types-cds_view.

          create_bdef_p(
          EXPORTING
                  "        io_put_operation = lo_bdef_put_operation
                          io_rap_bo_node   = root_node
                      ).
      ENDCASE.
    ENDIF.

    IF root_node->draft_enabled = abap_true.

      create_bil(
      EXPORTING
                      io_rap_bo_node   = root_node
                  ).

    ENDIF.

    LOOP AT root_node->all_childnodes INTO DATA(lo_bo_node).

      CASE lo_bo_node->data_source_type.

        WHEN lo_bo_node->data_source_types-abap_type OR lo_bo_node->data_source_types-structure.

          create_custom_entity(
                EXPORTING
                  io_rap_bo_node   = lo_bo_node
              ).

          create_custom_query(
                EXPORTING
                  io_rap_bo_node   = lo_bo_node
              ).

        WHEN OTHERS.

          create_i_cds_view(
            EXPORTING
              io_rap_bo_node   = lo_bo_node
          ).

          create_p_cds_view(
               EXPORTING
                 io_rap_bo_node   = lo_bo_node
             ).

          create_mde_view(
          EXPORTING
            io_rap_bo_node   = lo_bo_node
        ).

      ENDCASE.

      IF lo_bo_node->get_implementation_type( ) = lo_bo_node->implementation_type-unmanged_semantic.
        create_control_structure(
            EXPORTING
                        io_rap_bo_node   = lo_bo_node
                    ).
      ENDIF.

      IF root_node->draft_enabled = abap_true.

        create_bil(
        EXPORTING
                        io_rap_bo_node   = lo_bo_node
                    ).

      ENDIF.



    ENDLOOP.

    IF root_node->get_implementation_type( ) = root_node->implementation_type-unmanged_semantic.
      create_control_structure(
     EXPORTING
       io_rap_bo_node   = root_node
   ).
    ENDIF.

    IF root_node->publish_service = abap_true.
      create_service_definition(
        EXPORTING
          io_rap_bo_node   = root_node
      ).
    ENDIF.

    "start to create all objects beside service binding

    IF root_node->skip_activation = abap_true.
**********************************************************************
** Start of deletion 2020
**********************************************************************
      lo_result = mo_put_operation->execute( VALUE #( ( xco_cp_generation=>put_operation_option->skip_activation ) ) ).
**********************************************************************
** End of deletion 2020
**********************************************************************
**********************************************************************
** End of insertion 2020
**********************************************************************
*      lo_result = mo_put_operation->execute(  ).
**********************************************************************
** End of insertion 2020
**********************************************************************
    ELSE.
      lo_result = mo_put_operation->execute(  ).
    ENDIF.
    lo_findings = lo_result->findings.
    lt_findings = lo_findings->get( ).

    IF lt_findings IS NOT INITIAL.
      APPEND 'Messages from XCO framework' TO rt_todos.
      LOOP AT lt_findings INTO DATA(ls_findings).
        APPEND | Type: { ls_findings->object_type } Object name: { ls_findings->object_name } Message: { ls_findings->message->get_text(  ) }  | TO rt_todos.
      ENDLOOP.
    ENDIF.

    "if skip_activation is true the service definition will not be activated.
    "it is hence not possible to generate a service binding on top
    IF root_node->publish_service = abap_true AND root_node->skip_activation = abap_false.

      create_service_binding(
        EXPORTING
          io_rap_bo_node   = root_node
      ).

      "service binding needs a separate put operation
      lo_result = mo_srvb_put_operation->execute(  ).

      lo_findings = lo_result->findings.
      DATA(lt_srvb_findings) = lo_findings->get( ).

      IF lt_srvb_findings IS NOT INITIAL.
        APPEND 'Messages from XCO framework (Service Binding)' TO rt_todos.
        LOOP AT lt_srvb_findings INTO ls_findings.
          APPEND | Type: { ls_findings->object_type } Object name: { ls_findings->object_name } Message: { ls_findings->message->get_text(  ) }  | TO rt_todos.
        ENDLOOP.
      ENDIF.


    ENDIF.


    "if skip_activation is true the service definition will not be activated.
    "it is hence not possible to generate a service binding on top
    "we will thus have no service binding that can be used for registration

**********************************************************************
** Begin of deletion 2020
**********************************************************************


    IF root_node->manage_business_configuration = abap_true AND root_node->skip_activation = abap_false.

      APPEND 'Messages from business configuration registration' TO rt_todos.

      DATA(lo_business_configuration) = mbc_cp_api=>business_configuration(
        iv_identifier =  root_node->manage_business_config_names-identifier
        iv_namespace  = root_node->manage_business_config_names-namespace
      ).

      TRY.



          lo_business_configuration->create(
            iv_name            = root_node->manage_business_config_names-name
            iv_description     = root_node->manage_business_config_names-description
            iv_service_binding = CONV #( to_upper( root_node->rap_root_node_objects-service_binding ) )
            iv_service_name    = CONV #( to_upper( root_node->rap_root_node_objects-service_definition ) )

            iv_service_version = 0001
            iv_root_entity_set = root_node->entityname
            iv_transport       = CONV #( root_node->transport_request )
**********************************************************************
** Begin of deletion 2105
**********************************************************************
*            iv_skip_root_entity_list_rep = root_node->is_virtual_root(  )
**********************************************************************
** End of deletion 2105
**********************************************************************
          ).

          APPEND |{ root_node->manage_business_config_names-identifier } registered successfully.| TO rt_todos.

        CATCH cx_mbc_api_exception INTO DATA(lx_mbc_api_exception).
          DATA(lt_messages) = lx_mbc_api_exception->if_xco_news~get_messages( ).

          LOOP AT lt_messages INTO DATA(lo_message).
            " Use lo_message->get_text( ) to get the error message.
            "out->write( lo_message->get_text( ) ).
            APPEND lo_message->get_text( ) TO rt_todos.
          ENDLOOP.
      ENDTRY.

    ENDIF.
**********************************************************************
** End of deletion 2020
**********************************************************************
  ENDMETHOD.

  METHOD create_custom_entity.

    DATA ls_condition_components TYPE ts_condition_components.
    DATA lt_condition_components TYPE tt_condition_components.
    DATA lo_field TYPE REF TO if_xco_gen_ddls_s_fo_field .

    DATA(lo_specification) = mo_put_operation->for-ddls->add_object( io_rap_bo_node->rap_node_objects-custom_entity
     )->set_package( mo_package
     )->create_form_specification( ).

    "create a custom entity
    DATA(lo_view) = lo_specification->set_short_description( |CDS View for { io_rap_bo_node->rap_node_objects-alias  }|
      )->add_custom_entity( ).

    " Annotations can be added to custom entities.
    lo_view->add_annotation( 'ObjectModel.query.implementedBy' )->value->build( )->add_string( |ABAP:{ io_rap_bo_node->rap_node_objects-custom_query_impl_class }| ).

    "@ObjectModel.query.implementedBy:'ABAP:/DMO/CL_TRAVEL_UQ'

    IF io_rap_bo_node->is_root( ).
      lo_view->set_root( ).
    ELSE.

      CASE io_rap_bo_node->get_implementation_type(  ) .

        WHEN  /dmo/cl_rap_node=>implementation_type-unmanged_semantic .

          CLEAR ls_condition_components.
          CLEAR lt_condition_components.

          LOOP AT io_rap_bo_node->parent_node->semantic_key INTO DATA(ls_semantic_key).
            ls_condition_components-association_name = '_' && io_rap_bo_node->parent_node->rap_node_objects-alias.
            ls_condition_components-association_field = ls_semantic_key-cds_view_field.
            ls_condition_components-projection_field = ls_semantic_key-cds_view_field.
            APPEND ls_condition_components TO lt_condition_components.
          ENDLOOP.

          DATA(lo_condition) = create_condition( lt_condition_components ).

      ENDCASE.

      lo_field = lo_view->add_field( xco_cp_ddl=>field( '_' && io_rap_bo_node->parent_node->rap_node_objects-alias ) ).
      lo_field->create_association( io_rap_bo_node->parent_node->rap_node_objects-custom_entity
       " )->set_cardinality( xco_cp_cds=>cardinality->one_to_n
        )->set_condition( lo_condition )->set_to_parent( ).

      IF io_rap_bo_node->is_grand_child_or_deeper(  ).

        CASE io_rap_bo_node->get_implementation_type(  ) .

          WHEN  /dmo/cl_rap_node=>implementation_type-unmanged_semantic .

            CLEAR ls_condition_components.
            CLEAR lt_condition_components.

            LOOP AT io_rap_bo_node->ROOT_node->semantic_key INTO DATA(ls_root_semantic_key).
              ls_condition_components-association_name = '_' && io_rap_bo_node->root_node->rap_node_objects-alias.
              ls_condition_components-association_field = ls_root_semantic_key-cds_view_field.
              ls_condition_components-projection_field = ls_root_semantic_key-cds_view_field.
              APPEND ls_condition_components TO lt_condition_components.
            ENDLOOP.

            lo_condition = create_condition( lt_condition_components ).

        ENDCASE.

        lo_field = lo_view->add_field( xco_cp_ddl=>field( '_' && io_rap_bo_node->root_node->rap_node_objects-alias ) ).
        lo_field->create_association( io_rap_bo_node->parent_node->rap_node_objects-custom_entity
         " )->set_cardinality( xco_cp_cds=>cardinality->one_to_n
          )->set_condition( lo_condition )->set_to_parent(  ).

      ENDIF.

    ENDIF.

    " Data source.

    IF io_rap_bo_node->has_childs(  ).   " create_item_objects(  ).
      " Composition.

      "change to a new property "childnodes" which only contains the direct childs
      LOOP AT io_rap_bo_node->childnodes INTO DATA(lo_childnode).

        " Sample field with composition:
        lo_field = lo_view->add_field( xco_cp_ddl=>field( '_' && lo_childnode->rap_node_objects-alias  ) ).
        lo_field->create_composition( lo_childnode->rap_node_objects-custom_entity
       )->set_cardinality( xco_cp_cds=>cardinality->zero_to_n ).



      ENDLOOP.

    ENDIF.

    "Client field does not need to be specified in client-specific CDS view
    LOOP AT io_rap_bo_node->lt_fields  INTO  DATA(ls_header_fields) WHERE  name  <> io_rap_bo_node->field_name-client . "   co_client.

      IF ls_header_fields-key_indicator = abap_true.
        lo_field = lo_view->add_field( xco_cp_ddl=>field( ls_header_fields-cds_view_field )
           )->set_key( ). "->set_alias(  ls_header_fields-cds_view_field  ).
      ELSE.
        lo_field = lo_view->add_field( xco_cp_ddl=>field( ls_header_fields-cds_view_field )
           ). "->set_alias( ls_header_fields-cds_view_field ).
      ENDIF.

      IF ls_header_fields-is_data_element = abap_true.
        lo_field->set_type( xco_cp_abap_dictionary=>data_element( ls_header_fields-data_element ) ).
      ENDIF.
      IF ls_header_fields-is_built_in_type = abAP_TRUE.
        lo_field->set_type( xco_cp_abap_dictionary=>built_in_type->for(
                                        iv_type     =  ls_header_fields-built_in_type
                                        iv_length   = ls_header_fields-built_in_type_length
                                        iv_decimals = ls_header_fields-built_in_type_decimals
                                        ) ).
      ENDIF.

      "add @Semantics annotation for currency code
      IF ls_header_fields-currencycode IS NOT INITIAL.
        READ TABLE io_rap_bo_node->lt_fields INTO DATA(ls_field) WITH KEY name = to_upper( ls_header_fields-currencycode ).
        IF sy-subrc = 0.
          "for example @Semantics.amount.currencyCode: 'CurrencyCode'
          lo_field->add_annotation( 'Semantics.amount.currencyCode' )->value->build( )->add_string( CONV #( ls_field-cds_view_field ) ).
        ENDIF.
      ENDIF.

      "add @Semantics annotation for unit of measure
      IF ls_header_fields-unitofmeasure IS NOT INITIAL.
        CLEAR ls_field.
        READ TABLE io_rap_bo_node->lt_fields INTO ls_field WITH KEY name = to_upper( ls_header_fields-unitofmeasure ).
        IF sy-subrc = 0.
          "for example @Semantics.quantity.unitOfMeasure: 'QuantityUnit'
          lo_field->add_annotation( 'Semantics.quantity.unitOfMeasure' )->value->build( )->add_string( CONV #( ls_field-cds_view_field ) ).
        ENDIF.
      ENDIF.

      CASE ls_header_fields-name.
        WHEN io_rap_bo_node->field_name-created_at.
          lo_field->add_annotation( 'Semantics.systemDateTime.createdAt' )->value->build( )->add_boolean( abap_true ).
        WHEN io_rap_bo_node->field_name-created_by.
          lo_field->add_annotation( 'Semantics.user.createdBy' )->value->build( )->add_boolean( abap_true ).
        WHEN io_rap_bo_node->field_name-last_changed_at.
          lo_field->add_annotation( 'Semantics.systemDateTime.lastChangedAt' )->value->build( )->add_boolean( abap_true ).
        WHEN io_rap_bo_node->field_name-last_changed_by.
          lo_field->add_annotation( 'Semantics.user.lastChangedBy' )->value->build( )->add_boolean( abap_true ).
        WHEN io_rap_bo_node->field_name-local_instance_last_changed_at.
          lo_field->add_annotation( 'Semantics.systemDateTime.localInstanceLastChangedAt' )->value->build( )->add_boolean( abap_true ).
        WHEN io_rap_bo_node->field_name-local_instance_last_changed_by.
          lo_field->add_annotation( 'Semantics.user.localInstanceLastChangedBy' )->value->build( )->add_boolean( abap_true ).
      ENDCASE.

    ENDLOOP.

    "add associations

    LOOP AT io_rap_bo_node->lt_association INTO DATA(ls_assocation).

      CLEAR ls_condition_components.
      CLEAR lt_condition_components.
      LOOP AT ls_assocation-condition_components INTO DATA(ls_components).
        ls_condition_components-association_field =  ls_components-association_field.
        ls_condition_components-projection_field = ls_components-projection_field.
        ls_condition_components-association_name = ls_assocation-name.
        APPEND ls_condition_components TO lt_condition_components.
      ENDLOOP.

      lo_condition = create_condition( lt_condition_components ).

      lo_field = lo_view->add_field( xco_cp_ddl=>field( ls_assocation-name ) ).

      DATA(lo_association) = lo_field->create_association( io_rap_bo_node->parent_node->rap_node_objects-cds_view_i
       " )->set_cardinality( xco_cp_cds=>cardinality->one_to_n
        )->set_condition( lo_condition ).

      CASE ls_assocation-cardinality .
        WHEN /dmo/cl_rap_node=>cardinality-one.
          lo_association->set_cardinality(  xco_cp_cds=>cardinality->one ).
        WHEN /dmo/cl_rap_node=>cardinality-one_to_n.
          lo_association->set_cardinality(  xco_cp_cds=>cardinality->one_to_n ).
        WHEN /dmo/cl_rap_node=>cardinality-zero_to_n.
          lo_association->set_cardinality(  xco_cp_cds=>cardinality->zero_to_n ).
        WHEN /dmo/cl_rap_node=>cardinality-zero_to_one.
          lo_association->set_cardinality(  xco_cp_cds=>cardinality->zero_to_one ).
        WHEN /dmo/cl_rap_node=>cardinality-one_to_one.
          "@todo: currently association[1] will be generated
          "fix available with 2008 HFC2
          lo_association->set_cardinality(  xco_cp_cds=>cardinality->range( iv_min = 1 iv_max = 1 ) ).
      ENDCASE.

    ENDLOOP.

    LOOP AT       io_rap_bo_node->lt_additional_fields INTO DATA(additional_fields) WHERE cds_interface_view = abap_true.
      lo_field = lo_view->add_field( xco_cp_ddl=>expression->for( additional_fields-name )  ).
      IF additional_fields-cds_view_field IS NOT INITIAL.
        lo_Field->set_alias( additional_fields-cds_view_field ).
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD create_custom_query.


    DATA(lo_specification) = mo_put_operation->for-clas->add_object(  io_rap_bo_node->rap_node_objects-custom_query_impl_class
                                    )->set_package( mo_package
                                    )->create_form_specification( ).


    lo_specification->set_short_description( 'Custom query implementation' ).


    lo_specification->definition->add_interface( 'if_rap_query_provider' ).
    lo_specification->implementation->add_method( |if_rap_query_provider~select|
      )->set_source( VALUE #(
     ( |DATA business_data TYPE TABLE OF { io_rap_bo_node->data_source_name }.  | )
     ( |DATA(top)     = io_request->get_paging( )->get_page_size( ). | )
     ( |DATA(skip)    = io_request->get_paging( )->get_offset( ).| )
     ( |DATA(requested_fields)  = io_request->get_requested_elements( ).| )
     ( |DATA(sort_order)    = io_request->get_sort_elements( ).| )
     ( |TRY.| )
     ( | DATA(filter_condition) = io_request->get_filter( )->get_as_ranges( ).| )
     ( | "Here you have to implement your custom query| )
     ( |io_response->set_total_number_of_records( lines( business_data ) ).| )
     ( | io_response->set_data( business_data ).| )
     ( |CATCH cx_root INTO DATA(exception).| )
     ( |DATA(exception_message) = cl_message_helper=>get_latest_t100_exception( exception )->if_message~get_longtext( ).| )
     ( |ENDTRY.| )
      ) ).



  ENDMETHOD.

ENDCLASS.
