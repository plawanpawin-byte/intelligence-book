<!-- job=paper-q17 backend=mlx:Qwen3-1.7B-4bit seconds=201 calls=14 prompt_tokens=14281 gen_tokens=5419 source_chars=10185 source_tokens=2468 note_chars=13395 metrics={'chars': 13395, 'copy_ratio': 0.132, 'fillers': 2, 'dup_headings': 1, 'sections': 8, 'callouts': 22} -->
# How Transformers Make Language Models Smart and Fast

The number of possible sequences in language is astronomical — there are infinitely many ways to combine words into sentences. But with transformers, we can focus on what's relevant and ignore what's not. This note explains how transformers help models understand and generate text efficiently.

> [!summary] Overview  
> Transformations like self-attention and multi-head attention allow models to focus on relevant parts of the input. Self-attention compares every token with every other in a sequence, while cross-attention helps in decoding. The KV cache saves computation during generation, and positional encodings restore word order. Transformers balance efficiency and effectiveness by reducing quadratic complexity through careful scaling and parallel processing.

## Attention Mechanism: How Models Remember What They Need

Before 2017, most models for sequence tasks were built from **recurrent neural networks (RNNs)**. These models read a sentence one token at a time and compress information into a fixed-size hidden state vector $ h_t = f(h_{t-1}, x_t) $. This design has two major weaknesses: sequential computation and loss of early-token relevance.

> [!warning] Early tokens are important
> RNNs forget earlier parts of the input, which can hurt performance in tasks like translation or text generation.

### Attention Mechanism: A Soft Dictionary Lookup

Attention is a way to relax the strict matching rule of a dictionary. Instead of retrieving exactly what you ask for, it compares a query with every key and converts similarity scores into weights that sum to one. These weights are then used to produce a weighted average of all values.

- **Query** = the part of the input you're interested in
- **Key** = a representation of a word or token
- **Value** = the information associated with the key

> [!example] Attention helps models remember
> In translation tasks, attention allows the model to recall earlier parts of the sentence, improving accuracy and fluency.

- [ ] Understand how attention works in neural networks

## Transformer Attention: How Words Find Each Other

Each word in a sentence is represented by a vector $ x_i $ of size $ d_{\text{model}} $. These vectors are then transformed using three learned linear maps:

- **Query (Q)**: $ q_i = x_i W^Q $, resulting in an $ n \times d_k $ matrix.
- **Key (K)**: $ k_i = x_i W^K $, also $ n \times d_k $.
- **Value (V)**: $ v_i = x_i W^V $, $ n \times d_v $.

> [!tip] Remember:
> **Query** = how much token i cares about token j  
> **Key** = how much token j cares about token i  
> **Value** = what information is in the value vector

### The Attention Operation

The complete attention operation is:

$$
\text{Attention}(Q, K, V) = \text{softmax}(Q K^T / \sqrt{d_k}) V
$$

- $ Q K^T $ is an $ n \times n $ matrix where entry (i, j) measures how strongly token i attends to token j.
- Softmax applied row by row converts each row into a probability distribution over the n positions.
- Multiplying by $ V $ mixes the value vectors according to those probabilities.

> [!example] A word might care about multiple words in a sentence  
> For example, "dog" might care about "ball" and "cat" in a sentence like "The dog chased the ball and the cat."

### Why Divide by $ \sqrt{d_k} $? 

This normalization ensures that the attention weights are scaled appropriately. If components of $ q $ and $ k $ are independent with mean 0 and variance 1, their dot product has mean 0 and variance $ d_k $. For $ d_k = 64 $, scores typically have a standard deviation of 8, pushing softmax into a regime where one weight is close to 1 and the rest are close to 0.

> [!warning] Saturated regime:  
> Gradients become too small for learning to continue. This is why we need to normalize carefully.

### Summary

- **Query** tells how much token i cares about token j.
- **Key** tells how much token j cares about token i.
- **Value** holds the information from the value vector.
- Softmax ensures that attention weights sum to 1, giving each word a fair chance of being selected.

## Transformer Attention: How Weights Get Smaller and Better Focused

In transformers, attention mechanisms help the model focus on relevant parts of the input. This process is guided by scaling to ensure fairness among different tokens.

> [!tip] Remember:
> **Scaling by $ 1/\sqrt{d_k} $** restores unit variance and keeps the softmax in a well-behaved range.

### Worked Example Explained

Let’s say we have three tokens with $ d_k = 4 $. The raw scores (before scaling) are: (8, 4, 0).

- After scaling by $ 1/\sqrt{4} = 0.5 $, the scores become: (4, 2, 0).
- Now, the softmax calculation gives weights ≈ (0.87, 0.12, 0.02).

> [!example] Softmax highlights the most relevant token
> Output for token 1 is $ 0.87 v_1 + 0.12 v_2 + 0.02 v_3 $: mostly its own value, with small contribution from token 2.

### Without Scaling

If we don’t scale, the raw scores would be ≈ (0.98, 0.02, 0.00), which means the model places more weight on the first token and ignores the others — this is called a "harder" choice.

## Self-Attention vs. Cross-Attention: How Models Understand Language

In encoder-decoder models, two types of attention mechanisms help the model understand and generate text.

### Self-Attention
Self-attention occurs when **Q**, **K**, and **V** are all computed from the same sequence. Each token builds its own representation by gathering information from other tokens in the same sentence.

> [!tip] Remember:
> **Self-attention** = each token gathers info from others in the same sentence.

### Cross-Attention
Cross-attention is used in the decoder. Queries come from the decoder, while keys and values come from the encoder's output.

> [!example] Cross-attention helps the model understand context from earlier parts of the text.

### Causal Mask
To prevent a language model from looking ahead during prediction, a **causal mask** is applied. Before the softmax, every score (i, j) with j > i is set to -∞, making those weights zero.

> [!warning] This prevents the model from using future information but may not always be perfect.

### Multi-Head Attention
Multi-head attention processes multiple attention operations in parallel. Each head uses its own projection matrices $W_i^Q$, $W_i^K$, and $W_i^V$ to map into a smaller sub-space.

> [!definition] Multi-head attention = multiple attention heads working together.

### Final Output
The final output of all heads is concatenated and passed through a linear map $W^O$:  
$$
\text{MultiHead}(Q, K, V) = \text{Concat}(\text{head}_1, ..., \text{head}_h) W^O \text{head}_i = \text{Attention}(Q W_i^Q, K W_i^K, V W_i^V)
$$

> [!example] This allows the model to understand relationships between words in context.

### Model Parameters
In the original base model:
- $d_{\text{model}} = 512$
- $h = 8$ heads
- Each head uses $d_k = d_v = 512 / 8 = 64$

> [!tip] The smaller sub-space helps with parallel processing.

### Specialization of Heads
Empirically, different heads specialize in tasks like tracking previous tokens, linking pronouns to nouns, or following syntactic relations.

> [!warning] Heads do not always have a clear or predictable meaning.

### Cautions
Heads do not always have a clear or predictable meaning. They can be specialized for specific tasks but may not always align with the overall context.

## How Transformers Handle Attention and Computational Cost: A Story of Complexity and Efficiency

Transformers are powerful models because they efficiently handle attention and computation, but understanding how they work requires breaking down key ideas.

### Self-Attention Mechanism: Comparing Every Token

- **Self-attention** compares every token with every other token in a sequence.  
- For a sequence of length $ n $, this leads to a time and memory complexity of $ O(n^2 d) $, where $ d $ is the dimension of each token.  
- When $ n = 1,000 $, there are one million entries per head; when $ n = 100,000 $, it becomes ten billion entries.

### Recurrent Layers: Sequential Computation

- **Recurrent layers** cost $ O(n d^2) $ but must be computed sequentially.  
- This means that for large sequences, the computation can become very expensive and time-consuming.

### Early Transformers Were Limited by Quadratic Cost

- The quadratic cost is the main reason early Transformers were limited to contexts of 512 or 1,024 tokens.  
- With larger sequences, the computational burden becomes too high, making it impractical.

### Pre-Norm: Making Deep Stacks Easier

- **Pre-norm** (normalisation before sub-layer) makes very deep stacks easier to train.  
- This helps in stabilising training and reducing variance in gradients during deeper networks.

### Encoder-Only vs. Decoder-Only Models

- **Encoder-only models** like BERT see the whole input at once and are suited for classification and retrieval.  
- **Decoder-only models** like GPT family use a causal mask, which allows them to predict the next token based on previous ones.

### Encoder-Decoder: Translation and Summarization

- **Encoder-decoder** models like T5 keep both halves and are natural for translation and summarization.  
- This structure allows for bidirectional processing and better performance in tasks requiring understanding of context.

### FlashAttention: Memory-Efficient Exact Kernel

- **FlashAttention** is a memory-efficient exact kernel that avoids materialising the full $ n \times n $ matrix.  
- It significantly reduces memory usage, making it feasible for large sequences without sacrificing accuracy.

---

### Table Comparing Costs and Efficiency

| Task | Cost (O(n²d)) | FlashAttention | Notes |
|-----|----------------|------------------|-------|
| Self-attention | High | Low | For large n |
| Recurrent layers | Very high | Moderate | Sequential computation |
| Pre-norm | Low | No | Easier training |

---

### To Do List

- [ ] Understand how self-attention works in practice
- [ ] Learn why pre-norm helps with deep models
- [ ] Compare the cost of encoder vs. decoder models
- [ ] Explore how FlashAttention reduces memory usage

## Transformers: How They Focus on Words and Save Computation

Transformers are powerful models that help computers understand text by focusing on words and their relationships. Let's break down how they work.

### Attention Mechanism
During generation, the decoder-only model uses a "KV cache" to store keys and values from previous tokens. This means each new token only needs one new row of attention scores, which saves computation.

- **Positional encodings** restore word-order information, so the model knows the order of words in a sentence.
- **Multiple heads** allow the model to attend to several relationships at once, improving understanding of different parts of a sentence.

> [!tip] Remember:
> **KV cache** = stores key and value for quick access  
> **Positional encodings** = restore word order

### Scaling and Attention
The cost of full self-attention is quadratic in sequence length. This means that as the input grows, the computation becomes more expensive.

- **Scaling by sqrt(d_k)** prevents the softmax from saturating, making it more efficient.
- **Attention** computes a weighted average of value vectors using weights from a softmax over query-key similarities.

### Blocks and Computation
Each block consists of attention and feed-forward (FFN) layers with residual connections and LayerNorm.

> [!example] A large sentence has many score entries per head  
For a sequence of length n, the score matrix has n² entries per head.

### Exercises
1. With scores (6, 6, 0) and d_k = 9, which tokens receive the largest weights?
   - The token with score 6 will get the largest weight since it's the highest in the list.
2. Why can't a model without positional encodings distinguish "dog bites man" from "man bites dog"?
   - The model cannot recognize word order, so it doesn’t know which sentence comes first.

### Summary
- Modern models use **pre-norm** and efficient attention mechanisms like FlashAttention to save computation.

> [!warning] Don't forget:
> **Pre-norm** = adds residual connection before LayerNorm  
> **FlashAttention** = avoids full matrix materialization

## Key takeaways
- **Self-attention** allows models to attend to all tokens simultaneously, improving performance and efficiency over sequential models.

## Review questions

> [!question] Why did recurrent neural networks become less popular compared to attention-based methods?
> **Answer:** Recurrent neural networks have sequential computation and lose early-token relevance, while attention mechanisms provide a more efficient and effective way of modeling relationships between tokens.

> [!question] What is the purpose of scaling by $ 1/\sqrt{d_k} $ in attention mechanisms?
> **Answer:** Scaling by $ 1/\sqrt{d_k} $ restores unit variance and keeps the softmax in a well-behaved range.

> [!question] How does multi-head attention improve model performance?
> **Answer:** Multi-head attention processes multiple attention operations in parallel, allowing the model to attend to different parts of the input simultaneously.

> [!question] What is the role of positional encodings in transformers?
> **Answer:** Positional encodings restore word-order information, which is crucial for understanding context in sequence models.
