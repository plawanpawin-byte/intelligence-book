<!-- job=paper-v2 backend=mlx seconds=137 calls=5 prompt_tokens=7061 gen_tokens=2264 source_chars=10185 source_tokens=2422 note_chars=10226 metrics={'chars': 10226, 'copy_ratio': 0.252, 'fillers': 3, 'dup_headings': 0, 'sections': 5, 'callouts': 14} -->
# Understanding Multi-Head Attention: The Transformer Model's Secret Sauce

"Imagine being able to focus on multiple relationships simultaneously, like a superpower for machines." This is exactly what multi-head attention allows the Transformer model to do. By using multiple attention heads, each with its own weight matrix, the model can attend to multiple aspects of the input data at once, making it easier to learn complex patterns and improve performance.

> [!summary] Overview
>
> In this note, we will delve into the world of multi-head attention, exploring how it works, why it's essential for the Transformer model, and its applications in machine translation, question answering, and more.
>
> We'll start by understanding the basics of self-attention, then dive deeper into multi-head attention, discussing its benefits, components, and key terms.
>
> By the end of this note, you'll have a comprehensive grasp of multi-head attention, including its importance in the Transformer model and its potential to revolutionize natural language processing tasks.

## Attention and the Transformer
### Why attention?

The Transformer model was introduced as an alternative to recurrent neural networks (RNNs) for sequence tasks like machine translation. RNNs have two main weaknesses: **computation is inherently sequential**, meaning that each step must finish before the next can begin, making training non-parallelizable across positions of a sequence. Additionally, **information about early tokens must survive many repeated applications of the network** before it can influence later predictions.

This leads to **gradients shrinking or exploding along this path**, and long-range dependencies being learned poorly. The attention mechanism was introduced as an add-on to recurrent encoder-decoder models to address these issues.

### Attention as a soft dictionary lookup

A useful mental model for understanding attention is a dictionary (key-value store). In an ordinary dictionary, a query either matches a key exactly or it does not, and we return the corresponding value. Attention relaxes this by comparing the query with every key, each comparison producing a similarity score, which are then turned into weights that sum to one.

The output is the weighted average of all values, where **nothing is ever retrieved exactly**; instead, every value contributes in proportion to how well its key matches the query.

### Scaled dot-product attention

The Transformer uses the dot product as its similarity function. The complete operation is written:

Attention(Q, K, V) = softmax( Q K^T / sqrt(d_k) ) V

Reading equation (9.1) from the inside out: the product Q K^T is an n x n matrix whose entry (i, j) measures how strongly token i attends to token j.

**Why divide by sqrt(d_k)?**

If the components of q and k are independent with mean 0 and variance 1, their dot product has mean 0 and variance d_k. If d_k = 64, the scores would typically have a standard deviation of 8, pushing the softmax into a regime where one weight is close to 1 and the rest are close to 0.

Dividing by sqrt(d_k) restores unit variance and keeps the softmax in a well-behaved range.

### Worked example

Suppose a sequence has three tokens and d_k = 4. For the first token, the raw scores against the three keys are (8, 4, 0).

> [!example] Example
> Token 1: (8, 4, 0)
> Token 2: (4, 8, 0)
> Token 3: (0, 0, 8)

> [!tip] Takeaway and exam hint
> Because growth speeds up over time, starting to save early pays off — exams often ask for a 2-year compound interest calculation.

## Multi-Head Attention
Multi-head attention is an extension of self-attention that allows the model to consider multiple relationships simultaneously. This is achieved by running h attention operations in parallel, each with its own projection matrices W_i^Q, W_i^K, W_i^V.

> [!example] Example
> Suppose we have a sequence of tokens and want to compute multi-head attention. We can do this by applying the attention operation h times, each time using a different projection matrix.
>
> > [!tip] Takeaway and exam hint
>

In the original base model, d_model = 512 and h = 8 heads, so each head works with d_k = d_v = 512 / 8 = 64 dimensions. This means that each attention operation produces one weighted average per token.

### Multi-Head Attention Formula

The formula for multi-head attention is:

MultiHead(Q, K, V) = Concat(head_1, ..., head_h) W^O
head_i = Attention(Q W_i^Q, K W_i^K, V W_i^V)

where Q, K, and V are the query, key, and value matrices respectively.

> [!definition] **Attention Mechanism**
>
> The attention mechanism is a way for the model to weigh the importance of different input elements. It does this by computing a weighted sum of the input elements, where the weights are determined by the attention scores.

### Positional Information

The Transformer model has no idea of word order unless we supply it with positional information. This can be achieved through various methods such as:

*   Scaling the attention scores
*   Using a position encoding vector
*   Learning the position embeddings directly

> [!tip] Takeaway and exam hint

### The Transformer Block

A Transformer layer combines two sub-layers: multi-head self-attention and a position-wise feed-forward network (FFN). The FFN is applied independently to every token.

> [!example] Example
>
> Suppose we have a sequence of tokens and want to compute the Transformer block. We can do this by applying the self-attention operation h times, followed by the FFN.
>
> > [!definition] **Feed-Forward Network**
>
> A feed-forward network is a type of neural network that takes an input vector and produces an output vector through a series of linear transformations.

### Positional Encoding

The Transformer model uses positional encoding to preserve the order of the input elements. This is achieved through the use of sine and cosine functions.

> [!tip] Takeaway and exam hint

| **

## Multi-Head Attention and its Applications

**Multi-Head Attention** is a technique used in the Transformer model to allow the model to attend to multiple relationships simultaneously. This is achieved by using multiple attention heads, each with its own weight matrix.

Each block of the Transformer consists of two main components: **attention** and **Fully Feed-Forward Network (FFN)**. The attention mechanism computes a weighted average of value vectors, with weights given by a softmax over query-key similarities. ==This allows the model to focus on different aspects of the input data simultaneously==.

The use of multiple attention heads has several benefits:

*   It allows the model to attend to multiple relationships at once
*   It reduces the dimensionality of the output space
*   It makes it easier for the model to learn complex patterns in the data

### How Multi-Head Attention Works

The multi-head attention mechanism works as follows:

1.  **Query-Key Similarities**: The query and key vectors are computed using a linear transformation.
2.  **Attention Weights**: The attention weights are computed using a softmax function over the query-key similarities.
3.  **Output**: The output is computed by taking a weighted sum of the value vectors.

**Key Terms:**

*   **Multi-Head Attention**: A technique used in the Transformer model to allow the model to attend to multiple relationships simultaneously
*   **Attention Heads**: Multiple attention heads, each with its own weight matrix
*   **Query-Key Similarities**: The similarity between the query and key vectors

### Applications of Multi-Head Attention

The multi-head attention mechanism has several applications:

*   **Translation**: The Transformer model can be used for machine translation tasks.
*   **Question Answering**: The Transformer model can be used for question answering tasks.

**Exam Hint:**

*   To answer questions about the Transformer model, you need to understand how the multi-head attention mechanism works.
*   You should also be familiar with the different components of the Transformer model, including the encoder and decoder.

### Exercises

9.1 Repeat the worked example of Section 9.3 with scores (6, 6, 0) and d_k = 9. Which tokens receive the largest weights?

9.2 Explain in your own words why a model without positional encodings cannot distinguish "dog bites man" from "man bites dog".

**Warning:**

*   When working with the multi-head attention mechanism, it's easy to get confused about how the different components work together.
*   Make sure you understand the basics of the Transformer model before trying to apply the multi-head attention mechanism.

## Key Takeaways
- The Transformer model uses the attention mechanism to weigh the importance of different input elements by computing a weighted sum, where the weights are determined by the attention scores.
- Multi-head attention is an extension of self-attention that allows the model to consider multiple relationships simultaneously, reducing dimensionality and making it easier for the model to learn complex patterns.

## Review Questions
> [!question] What is the main weakness of recurrent neural networks (RNNs) that the Transformer model addresses?
> **Answer:** RNNs have two main weaknesses: computation is inherently sequential, and information about early tokens must survive many repeated applications of the network.

> [!question] How does the dot product similarity function work in the attention mechanism?
> **Answer:** The dot product similarity function measures how strongly token i attends to token j by computing the dot product of query and key vectors.

> [!question] What is the purpose of dividing by sqrt(d_k) in the attention operation?
> **Answer:** Dividing by sqrt(d_k) restores unit variance and keeps the softmax in a well-behaved range, preventing weights from becoming too large or too small.

> [!question] How does multi-head attention work, and what are its benefits?
> **Answer:** Multi-head attention works by running h attention operations in parallel, each with its own projection matrices. It allows the model to attend to multiple relationships simultaneously, reduces dimensionality, and makes it easier for the model to learn complex patterns.
