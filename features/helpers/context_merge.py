def merge_into_context(context, attr_name, new_data):
    """
    Merge a dictionary into an existing dictionary attribute on the context object.
    If the attribute doesn't exist, it initializes it with the new_data.
    If the new_data is not a dictionary, it simply sets the attribute to new_data.

    :param context: The object to update (e.g., Behave's context).
    :param attr_name: The name of the attribute to merge into or set.
    :param new_data: The data to merge into the attribute or set as the attribute.
    """
    existing_data = getattr(context, attr_name, None)

    if isinstance(existing_data, dict) and isinstance(new_data, dict):
        # Merge the dictionaries
        merged_data = {**existing_data, **new_data}
        setattr(context, attr_name, merged_data)
    else:
        # Set the new data directly
        setattr(context, attr_name, new_data)
