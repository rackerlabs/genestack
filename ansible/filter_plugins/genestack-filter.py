def bit_length_power_of_2(value):
    """Return the smallest power of 2 greater than a numeric value.
    :param value: Number to find the smallest power of 2
    :type value: ``int``
    :returns: ``int``
    """
    return 2 ** (int(value) - 1).bit_length()


class FilterModule(object):
    """Ansible jinja2 filters."""

    @staticmethod
    def filters():
        return {"bit_length_power_of_2": bit_length_power_of_2}
