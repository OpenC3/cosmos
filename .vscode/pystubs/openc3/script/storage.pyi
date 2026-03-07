from typing import IO, List, Optional, overload

# --- File Operations ---

def get_target_file(file_path: str, original: bool = False) -> IO:
    """
    Returns a file handle to a file in the target directory.

    Args:
        file_path (str): The path to the file on the target.
        original (bool): If True, retrieves the original version of the file, ignoring
                         any patches. Defaults to False.

    Returns:
        IO: A file-like object for the requested file.
    """
    ...

def put_target_file(file_path: str, data: str | IO) -> None:
    """
    Writes a file to the target directory.

    Args:
        file_path (str): The path to the file on the target.
        data (str | IO): The data to write. Can be a string or a file-like object.
    """
    ...

def delete_target_file(file_path: str) -> None:
    """
    Deletes a file in the target directory.

    Args:
        file_path (str): The path to the file on the target.
    """
    ...

@overload
def open_file_dialog(
    title: str, message: Optional[str] = None, filter: Optional[str] = None
) -> IO: ...
def open_file_dialog(*args: str, **kwargs: str) -> IO:
    """
    Creates a file dialog box for the user to select a single file. The selected
    file handle is returned.

    Args:
        title (str): The title of the dialog box.
        message (Optional[str]): A message to display in the dialog box.
                                 Defaults to None.
        filter (Optional[str]): A filter for the file types to show (e.g., "*.txt").
                                Defaults to None.

    Returns:
        IO: A file-like object for the selected file.
    """
    ...

@overload
def open_files_dialog(
    title: str, message: Optional[str] = None, filter: Optional[str] = None
) -> List[IO]: ...
def open_files_dialog(*args: str, **kwargs: str) -> List[IO]:
    """
    Creates a file dialog box for the user to select multiple files. A list of
    the selected file handles is returned.

    Args:
        title (str): The title of the dialog box.
        message (Optional[str]): A message to display in the dialog box.
                                 Defaults to None.
        filter (Optional[str]): A filter for the file types to show (e.g., "*.txt").
                                Defaults to None.

    Returns:
        List[IO]: A list of file-like objects for the selected files.
    """
    ...

def open_bucket_dialog(title: str, message: str = "Open Bucket File") -> IO:
    """
    Creates a dialog box that allows the user to browse S3 bucket files and
    select one. It presents the available buckets (similar to Bucket Explorer)
    and allows navigating directories within the selected bucket. The selected
    file is downloaded and returned as a file object.

    Args:
        title (str): The title of the dialog box.
        message (str): A message to display in the dialog box.
                       Defaults to "Open Bucket File".

    Returns:
        IO: A file-like object for the selected file, with a `filename`
            attribute containing the name of the selected file.
    """
    ...
