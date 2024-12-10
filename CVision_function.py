import cv2
import numpy as np

def get_contours_and_vals(path: str):
    image = cv2.imread(path)

    hsv_image = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)

    lower_blue = np.array([100, 150, 0])
    upper_blue = np.array([140, 255, 255])
    mask = cv2.inRange(hsv_image, lower_blue, upper_blue)
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    output_image = image.copy()
    cv2.drawContours(output_image, contours, -1, (0, 128, 255), 2)

    count_of_contours = len(contours)

    return output_image, count_of_contours

