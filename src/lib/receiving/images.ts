import {
  receiptPhotoCompressThresholdBytes,
  receiptPhotoMaxDimension,
  validateReceiptPhoto,
} from "./types";

function loadImage(file: File) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const image = new Image();
    image.onload = () => {
      URL.revokeObjectURL(url);
      resolve(image);
    };
    image.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("Unable to read the selected photo."));
    };
    image.src = url;
  });
}

export async function prepareReceiptPhoto(file: File) {
  const validationError = validateReceiptPhoto(file);
  if (validationError) throw new Error(validationError);
  if (
    file.size <= receiptPhotoCompressThresholdBytes ||
    !["image/jpeg", "image/png", "image/webp"].includes(file.type)
  ) {
    return file;
  }

  const image = await loadImage(file);
  const scale = Math.min(1, receiptPhotoMaxDimension / Math.max(image.width, image.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(image.width * scale));
  canvas.height = Math.max(1, Math.round(image.height * scale));
  const context = canvas.getContext("2d");
  if (!context) return file;
  context.drawImage(image, 0, 0, canvas.width, canvas.height);

  const blob = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob(resolve, "image/jpeg", 0.82),
  );
  if (!blob || blob.size >= file.size) return file;
  return new File([blob], file.name.replace(/\.[^.]+$/, "") + ".jpg", {
    type: "image/jpeg",
    lastModified: file.lastModified,
  });
}
