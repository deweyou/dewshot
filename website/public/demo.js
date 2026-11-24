const canvas = document.querySelector("#art");
const context = canvas.getContext("2d");
const button = document.querySelector("#crop");
const selection = document.querySelector(".selection");
const caption = document.querySelector("#demo-caption");

function drawLandscape() {
  const sky = context.createLinearGradient(0, 0, 0, 620);
  sky.addColorStop(0, "#aaccc4");
  sky.addColorStop(0.75, "#f1dfb4");
  context.fillStyle = sky;
  context.fillRect(0, 0, 840, 620);
  context.fillStyle = "#fff0bf";
  context.beginPath();
  context.arc(575, 213, 52, 0, Math.PI * 2);
  context.fill();
  const hills = [
    ["#98b9a8", 345, -23, 35, 8],
    ["#6b998d", 375, 46, 50, 74],
    ["#44796e", 428, -48, 18, 156],
    ["#27584f", 500, 28, 48, 280],
    ["#193f3b", 563, -25, 28, 92],
  ];
  for (const [color, base, wave, ripple, shift] of hills) {
    context.beginPath();
    context.moveTo(0, 620);
    for (let x = 0; x <= 840; x += 2) {
      context.lineTo(
        x,
        base +
          wave * Math.sin((x + shift) / 113) +
          ripple * Math.cos((x + shift) / 195),
      );
    }
    context.lineTo(840, 620);
    context.closePath();
    context.fillStyle = color;
    context.fill();
  }
}

drawLandscape();
button.hidden = false;
button.addEventListener("click", () => {
  if (selection.hidden) {
    drawLandscape();
    caption.textContent = "框选截图 · 交互演示";
    button.textContent = "截取选区";
  } else {
    const crop = document.createElement("canvas");
    crop.width = 580;
    crop.height = 372;
    crop.getContext("2d").drawImage(canvas, 134, 136, 580, 372, 0, 0, 580, 372);
    context.fillStyle = "#dfe9dc";
    context.fillRect(0, 0, 840, 620);
    context.drawImage(crop, 130, 124);
    caption.textContent = "选区预览 · 580 × 372";
    button.textContent = "重新框选";
  }
  selection.hidden = !selection.hidden;
});
