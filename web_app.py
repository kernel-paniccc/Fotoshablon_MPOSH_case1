import csv

import flet as ft
from PIL import Image
import os
from flet import Theme
from CVision_function import get_contours_and_vals
import cv2

SAVE_DIRECTORY = "converted_images/"
os.makedirs(SAVE_DIRECTORY, exist_ok=True)

async def main(page: ft.Page):
    page.fonts = {
        "RobotoSlab": "https://github.com/google/fonts/raw/main/apache/robotoslab/RobotoSlab%5Bwght%5D.ttf"
    }

    page.title = 'Подготовка фотошаблона'
    page.theme = Theme(color_scheme_seed='cyan', font_family='RobotoSlab')
    page.update()
    page.vertical_alignment = ft.MainAxisAlignment.CENTER

    def pick_files_result(e: ft.FilePickerResultEvent):
        selected_files.value = (
            ", ".join(map(lambda f: f.name, e.files)) if e.files else page.open(snack_bar_error)
        )
        selected_files.update()
        reg_btn.disabled = not e.files
        reg_btn.update()

        if e.files:
            page.selected_images = e.files

    pick_files_dialog = ft.FilePicker(on_result=pick_files_result)
    selected_files = ft.Text()

    snack_bar_error = ft.SnackBar(
        ft.Row(
            [ft.Text("Некорректные данные", color=ft.Colors.RED_500, size=20)],
            alignment=ft.MainAxisAlignment.CENTER
        ),
        bgcolor=ft.Colors.GREY_900,
    )

    snack_bar_success = ft.SnackBar(
        ft.Row(
            [ft.Text("Конвертация успешна!", color=ft.Colors.GREEN_500, size=20)],
            alignment=ft.MainAxisAlignment.CENTER
        ),
        bgcolor=ft.Colors.GREY_900,
    )

    page.overlay.append(pick_files_dialog)

    upload_btn = ft.ElevatedButton(
        "Загрузите файл", icon=ft.Icons.UPLOAD_FILE,
        on_click=lambda _: pick_files_dialog.pick_files(allow_multiple=True, allowed_extensions=['jpg']),
        width=500
    )

    def get_img(path):
        im = Image.open(path)
        im.show()

    def write_csv(file_name, count_objects):
        with open('data.csv', 'a', newline='', encoding='utf-8') as file:
            writer = csv.writer(file)
            writer.writerow([file_name, count_objects])

    def convert_images(e):
        if hasattr(page, 'selected_images'):
            for file in page.selected_images:
                path = file.path
                try:
                    img, values = get_contours_and_vals(str(path))
                    save_path = os.path.join(SAVE_DIRECTORY, f"{file.name}")
                    cv2.imwrite(save_path, img)
                    write_csv(file.name, values)
                except:
                    page.open(snack_bar_error)
                    btn_container.controls.clear()
                    page.update()
                finally:
                    open_btn = ft.ElevatedButton(
                        text=f"Открыть {file.name}",
                        icon=ft.Icons.DOWNLOAD,
                        on_click=lambda e, path=save_path: get_img(path)
                    )

                    file_btn = ft.ElevatedButton(
                        text=f"Открыть data.csv",
                        icon=ft.Icons.DOWNLOAD,
                        on_click=lambda e: os.startfile('data.csv')
                    )
                    btn_container.controls.clear()
                    if len(btn_container.controls) <= 1:
                        btn_container.controls.append(open_btn)
                        btn_container.controls.append(file_btn)
                page.open(snack_bar_success)
                page.update()

    reg_btn = ft.ElevatedButton(text='Конвертировать', disabled=True, on_click=convert_images)
    btn_container = ft.Column(spacing=10)

    main_page = ft.Container(
        content=ft.Column(
            [
                ft.Text('Подготовка фотошаблона', size=50, color=ft.Colors.CYAN_400),
                upload_btn, selected_files,
                reg_btn,
                btn_container
            ],
            alignment=ft.MainAxisAlignment.CENTER,
            spacing=20
        ),
        padding=20,
        border_radius=10,
        alignment=ft.alignment.center
    )


    page.add(main_page)


if __name__ == '__main__':
    ft.app(target=main)
